import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/backup/backup_crypto.dart';

void main() {
  late Directory dir;
  late BackupKey key;

  setUpAll(() async {
    key = await BackupCrypto.deriveKey(
      'correct horse',
      params: KdfParams.fastForTests,
    );
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('tk_crypto'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List data(int length, [int seed = 1]) {
    final r = Random(seed);
    return Uint8List.fromList(List.generate(length, (_) => r.nextInt(256)));
  }

  Future<File> encrypt(
    Uint8List plain, {
    BackupKey? k,
    bool isolate = false,
  }) async {
    final input = File('${dir.path}/in.bin')..writeAsBytesSync(plain);
    final output = File('${dir.path}/out.tkbackup');
    await BackupCrypto.encryptFile(input, output, k ?? key, inIsolate: isolate);
    return output;
  }

  Future<Uint8List> decrypt(File sealed, String passphrase) async {
    final out = File('${dir.path}/back.bin');
    await BackupCrypto.decryptFile(sealed, out, passphrase, inIsolate: false);
    return out.readAsBytesSync();
  }

  Future<BackupCryptoError?> failure(Future<Object?> Function() action) async {
    try {
      await action();
    } on BackupCryptoException catch (e) {
      return e.error;
    }
    return null;
  }

  group('key derivation', () {
    test(
      'is deterministic for a salt and differs between passphrases',
      () async {
        final a = await BackupCrypto.deriveKey(
          'abc',
          salt: key.salt,
          params: KdfParams.fastForTests,
        );
        final b = await BackupCrypto.deriveKey(
          'abc',
          salt: key.salt,
          params: KdfParams.fastForTests,
        );
        final c = await BackupCrypto.deriveKey(
          'abd',
          salt: key.salt,
          params: KdfParams.fastForTests,
        );
        expect(a.bytes, b.bytes);
        expect(a.bytes, isNot(c.bytes));
        expect(a.bytes, hasLength(32));
        expect(a.hex, matches(RegExp(r'^[0-9a-f]{64}$')));
      },
    );

    test('a fresh salt every time unless one is given', () async {
      final a = await BackupCrypto.deriveKey(
        'abc',
        params: KdfParams.fastForTests,
      );
      final b = await BackupCrypto.deriveKey(
        'abc',
        params: KdfParams.fastForTests,
      );
      expect(a.salt, isNot(b.salt));
      expect(a.salt, hasLength(16));
    });

    test('Bangla and long passphrases work', () async {
      final k = await BackupCrypto.deriveKey(
        'আমার দোকানের চাবি ১২৩',
        params: KdfParams.fastForTests,
      );
      expect(k.bytes, hasLength(32));
    });
  });

  group('round trip', () {
    for (final size in [
      0,
      1,
      100,
      BackupCrypto.chunkSize - 1,
      BackupCrypto.chunkSize,
      BackupCrypto.chunkSize + 1,
      BackupCrypto.chunkSize * 3 + 17,
    ]) {
      test('$size bytes', () async {
        final plain = data(size);
        final sealed = await encrypt(plain);
        expect(await decrypt(sealed, 'correct horse'), plain);
      });
    }

    test('works through a background isolate', () async {
      final plain = data(BackupCrypto.chunkSize + 5000, 9);
      final sealed = await encrypt(plain, isolate: true);
      final out = File('${dir.path}/iso.bin');
      await BackupCrypto.decryptFile(sealed, out, 'correct horse');
      expect(out.readAsBytesSync(), plain);
    });

    test('the file is bigger by header, framing and tags only', () async {
      final sealed = await encrypt(data(100));
      expect(sealed.lengthSync(), BackupCrypto.headerLength + 4 + 100 + 16);
    });

    test('encrypting twice gives different files (random nonce)', () async {
      final plain = data(500);
      final a = (await encrypt(plain)).readAsBytesSync();
      final b = (await encrypt(plain)).readAsBytesSync();
      expect(a, isNot(b));
    });

    test('plaintext does not appear in the file', () async {
      final marker = Uint8List.fromList('SECRET-CUSTOMER-NAME'.codeUnits);
      final sealed = await encrypt(marker);
      final text = String.fromCharCodes(sealed.readAsBytesSync());
      expect(text.contains('SECRET'), isFalse);
    });

    test('header is readable without the passphrase', () async {
      final sealed = await encrypt(data(10));
      final header = await BackupCrypto.readHeader(sealed);
      expect(header.salt, key.salt);
      expect(header.params.iterations, KdfParams.fastForTests.iterations);
    });
  });

  group('failure cases (S6-05)', () {
    test('wrong passphrase', () async {
      final sealed = await encrypt(data(2000));
      expect(
        await failure(() => decrypt(sealed, 'wrong')),
        BackupCryptoError.authenticationFailed,
      );
    });

    test('passphrase is case sensitive', () async {
      final sealed = await encrypt(data(2000));
      expect(
        await failure(() => decrypt(sealed, 'Correct horse')),
        BackupCryptoError.authenticationFailed,
      );
    });

    test('any flipped byte in the body is detected', () async {
      final sealed = await encrypt(data(5000));
      final bytes = sealed.readAsBytesSync();
      for (final position in [
        BackupCrypto.headerLength + 4, // first ciphertext byte
        BackupCrypto.headerLength + 2000, // middle
        bytes.length - 1, // inside the tag
      ]) {
        final copy = Uint8List.fromList(bytes)..[position] ^= 0x01;
        File('${dir.path}/bad.tkbackup').writeAsBytesSync(copy);
        expect(
          await failure(
            () => decrypt(File('${dir.path}/bad.tkbackup'), 'correct horse'),
          ),
          BackupCryptoError.authenticationFailed,
          reason: 'byte $position',
        );
      }
    });

    test('changing the header (salt, nonce) is detected', () async {
      final bytes = (await encrypt(data(300))).readAsBytesSync();
      for (final position in [14, 29, 30, 41]) {
        final copy = Uint8List.fromList(bytes)..[position] ^= 0x01;
        File('${dir.path}/bad.tkbackup').writeAsBytesSync(copy);
        expect(
          await failure(
            () => decrypt(File('${dir.path}/bad.tkbackup'), 'correct horse'),
          ),
          BackupCryptoError.authenticationFailed,
          reason: 'header byte $position',
        );
      }
    });

    test('cutting the file in the middle of a chunk', () async {
      final bytes = (await encrypt(data(5000))).readAsBytesSync();
      File('${dir.path}/cut.tkbackup')
          .writeAsBytesSync(bytes.sublist(0, bytes.length - 50));
      expect(
        await failure(
          () => decrypt(File('${dir.path}/cut.tkbackup'), 'correct horse'),
        ),
        BackupCryptoError.truncated,
      );
    });

    test('dropping whole trailing chunks is detected', () async {
      final plain = data(BackupCrypto.chunkSize * 2 + 10);
      final bytes = (await encrypt(plain)).readAsBytesSync();
      // Keep header + first chunk only.
      final firstChunkEnd =
          BackupCrypto.headerLength + 4 + BackupCrypto.chunkSize + 16;
      File('${dir.path}/cut.tkbackup')
          .writeAsBytesSync(bytes.sublist(0, firstChunkEnd));
      expect(
        await failure(
          () => decrypt(File('${dir.path}/cut.tkbackup'), 'correct horse'),
        ),
        BackupCryptoError.authenticationFailed,
      );
    });

    test('swapping two chunks is detected', () async {
      final plain = data(BackupCrypto.chunkSize * 2);
      final bytes = (await encrypt(plain)).readAsBytesSync();
      const frame = 4 + BackupCrypto.chunkSize + 16;
      final h = BackupCrypto.headerLength;
      final swapped = Uint8List.fromList([
        ...bytes.sublist(0, h),
        ...bytes.sublist(h + frame, h + 2 * frame),
        ...bytes.sublist(h, h + frame),
        ...bytes.sublist(h + 2 * frame),
      ]);
      File('${dir.path}/swap.tkbackup').writeAsBytesSync(swapped);
      expect(
        await failure(
          () => decrypt(File('${dir.path}/swap.tkbackup'), 'correct horse'),
        ),
        BackupCryptoError.authenticationFailed,
      );
    });

    test('not a backup at all', () async {
      File('${dir.path}/x.tkbackup')
          .writeAsBytesSync(Uint8List.fromList(List.filled(100, 7)));
      expect(
        await failure(() => decrypt(File('${dir.path}/x.tkbackup'), 'p')),
        BackupCryptoError.notABackup,
      );
      File('${dir.path}/short.tkbackup')
          .writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      expect(
        await failure(() => decrypt(File('${dir.path}/short.tkbackup'), 'p')),
        BackupCryptoError.notABackup,
      );
      File('${dir.path}/empty.tkbackup').writeAsBytesSync(Uint8List(0));
      expect(
        await failure(() => decrypt(File('${dir.path}/empty.tkbackup'), 'p')),
        BackupCryptoError.notABackup,
      );
    });

    test('a newer file version asks for an app update', () async {
      final bytes = (await encrypt(data(10))).readAsBytesSync();
      final copy = Uint8List.fromList(bytes)..[4] = 9;
      File('${dir.path}/v9.tkbackup').writeAsBytesSync(copy);
      expect(
        await failure(
          () => decrypt(File('${dir.path}/v9.tkbackup'), 'correct horse'),
        ),
        BackupCryptoError.unsupportedVersion,
      );
    });

    test('absurd cost parameters are refused, not obeyed', () async {
      final bytes = (await encrypt(data(10))).readAsBytesSync();
      final copy = Uint8List.fromList(bytes);
      ByteData.sublistView(copy).setUint32(5, 4000000); // ~4 GB of memory
      File('${dir.path}/evil.tkbackup').writeAsBytesSync(copy);
      expect(
        await failure(
          () => decrypt(File('${dir.path}/evil.tkbackup'), 'correct horse'),
        ),
        BackupCryptoError.badParameters,
      );
    });

    test(
      'a failed decryption never leaves the passphrase check to guesswork',
      () async {
        final sealed = await encrypt(data(100));
        // Same wrong answer for 20 different wrong passphrases.
        for (var i = 0; i < 20; i++) {
          expect(
            await failure(() => decrypt(sealed, 'guess $i')),
            BackupCryptoError.authenticationFailed,
          );
        }
      },
    );
  });
}

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Argon2id settings for turning a passphrase into a key (TD §6).
class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    this.parallelism = 1,
  });

  /// OWASP's minimum recommendation for Argon2id: 19 MiB, 2 passes. Roughly a
  /// second on a modest phone, which is fine for something done rarely.
  static const KdfParams standard = KdfParams(memoryKiB: 19456, iterations: 2);

  /// Very cheap settings so tests stay fast. Never used in the app.
  static const KdfParams fastForTests = KdfParams(memoryKiB: 64, iterations: 1);

  /// A file claiming more than this is rejected rather than trusted, so a
  /// crafted backup cannot make the phone run out of memory.
  static const int maxMemoryKiB = 262144;
  static const int maxIterations = 10;

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  bool get isSane =>
      memoryKiB >= 8 &&
      memoryKiB <= maxMemoryKiB &&
      iterations >= 1 &&
      iterations <= maxIterations &&
      parallelism >= 1 &&
      parallelism <= 4;
}

/// A key derived from the backup passphrase, with what is needed to derive
/// it again from the passphrase alone (the [salt] and [params] travel in every
/// backup file's header).
class BackupKey {
  const BackupKey({
    required this.salt,
    required this.bytes,
    required this.params,
  });

  final Uint8List salt;

  /// 32 secret bytes.
  final Uint8List bytes;
  final KdfParams params;

  /// Lower-case hex of the key, for use as a SQLCipher raw key.
  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// The file is not a readable backup, or the passphrase is wrong.
enum BackupCryptoError {
  notABackup,
  unsupportedVersion,
  badParameters,

  /// Wrong passphrase, or the file was changed / damaged.
  authenticationFailed,
  truncated,
}

class BackupCryptoException implements Exception {
  const BackupCryptoException(this.error);

  final BackupCryptoError error;

  @override
  String toString() => 'BackupCryptoException($error)';
}

/// Passphrase-based, authenticated encryption of backup files.
///
/// Format (all integers big-endian):
/// ```
/// "TKBK" | version=1 | memKiB u32 | iterations u32 | parallelism u8 |
/// salt[16] | baseNonce[12]                         -- header, 42 bytes
/// then repeated: length u32 | AES-256-GCM(chunk)+tag[16]
/// ```
/// The plaintext is cut into 1 MiB chunks so large photo collections never
/// have to fit in memory. Each chunk's nonce is the base nonce combined with
/// its index, and its associated data is the header, the index and a flag for
/// "last chunk", so reordering, dropping or truncating chunks is detected.
class BackupCrypto {
  const BackupCrypto._();

  static const int version = 1;
  static const int chunkSize = 1 << 20;
  static const int tagLength = 16;
  static const int headerLength = 42;
  static final List<int> _magic = 'TKBK'.codeUnits;

  static final AesGcm _aes = AesGcm.with256bits();

  /// Derives a key from [passphrase]; a fresh random salt unless [salt] is
  /// given (as when reading an existing backup).
  static Future<BackupKey> deriveKey(
    String passphrase, {
    Uint8List? salt,
    KdfParams params = KdfParams.standard,
  }) async {
    final usedSalt = salt ?? randomBytes(16);
    final kdf = Argon2id(
      parallelism: params.parallelism,
      memory: params.memoryKiB,
      iterations: params.iterations,
      hashLength: 32,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: usedSalt,
    );
    return BackupKey(
      salt: usedSalt,
      bytes: Uint8List.fromList(await key.extractBytes()),
      params: params,
    );
  }

  static final Random _random = Random.secure();

  static Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  // ---- file API -----------------------------------------------------------

  /// Encrypts [input] into [output] with [key]. Runs on a background isolate.
  static Future<void> encryptFile(
    File input,
    File output,
    BackupKey key, {
    bool inIsolate = true,
  }) {
    final job = _EncryptJob(input.path, output.path, key);
    return inIsolate ? Isolate.run(() => _encrypt(job)) : _encrypt(job);
  }

  /// Decrypts [input] into [output] using [passphrase]; the salt and cost are
  /// read from the file. Throws [BackupCryptoException].
  static Future<BackupKey> decryptFile(
    File input,
    File output,
    String passphrase, {
    bool inIsolate = true,
  }) async {
    final header = await readHeader(input);
    final key = await deriveKey(
      passphrase,
      salt: header.salt,
      params: header.params,
    );
    final job = _DecryptJob(input.path, output.path, key);
    if (inIsolate) {
      await Isolate.run(() => _decrypt(job));
    } else {
      await _decrypt(job);
    }
    return key;
  }

  /// Decrypts with an already derived key.
  static Future<void> decryptFileWithKey(
    File input,
    File output,
    BackupKey key, {
    bool inIsolate = true,
  }) {
    final job = _DecryptJob(input.path, output.path, key);
    return inIsolate ? Isolate.run(() => _decrypt(job)) : _decrypt(job);
  }

  /// Reads only the header: cheap, and lets the UI know the file is a backup
  /// before asking for the passphrase.
  static Future<BackupHeader> readHeader(File file) async {
    final raf = await file.open();
    try {
      final bytes = await raf.read(headerLength);
      return BackupHeader.parse(Uint8List.fromList(bytes));
    } finally {
      await raf.close();
    }
  }
}

/// Parsed file header.
class BackupHeader {
  const BackupHeader({
    required this.params,
    required this.salt,
    required this.baseNonce,
    required this.raw,
  });

  final KdfParams params;
  final Uint8List salt;
  final Uint8List baseNonce;

  /// The exact header bytes, used as associated data for every chunk.
  final Uint8List raw;

  factory BackupHeader.parse(Uint8List bytes) {
    if (bytes.length < BackupCrypto.headerLength) {
      throw const BackupCryptoException(BackupCryptoError.notABackup);
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != BackupCrypto._magic[i]) {
        throw const BackupCryptoException(BackupCryptoError.notABackup);
      }
    }
    if (bytes[4] != BackupCrypto.version) {
      throw const BackupCryptoException(BackupCryptoError.unsupportedVersion);
    }
    final view = ByteData.sublistView(bytes);
    final params = KdfParams(
      memoryKiB: view.getUint32(5),
      iterations: view.getUint32(9),
      parallelism: bytes[13],
    );
    if (!params.isSane) {
      throw const BackupCryptoException(BackupCryptoError.badParameters);
    }
    return BackupHeader(
      params: params,
      salt: Uint8List.fromList(bytes.sublist(14, 30)),
      baseNonce: Uint8List.fromList(bytes.sublist(30, 42)),
      raw: Uint8List.fromList(bytes.sublist(0, BackupCrypto.headerLength)),
    );
  }
}

// ---- isolate workers --------------------------------------------------------

class _EncryptJob {
  const _EncryptJob(this.input, this.output, this.key);
  final String input;
  final String output;
  final BackupKey key;
}

class _DecryptJob {
  const _DecryptJob(this.input, this.output, this.key);
  final String input;
  final String output;
  final BackupKey key;
}

Uint8List _nonceFor(Uint8List base, int index) {
  final nonce = Uint8List.fromList(base);
  // Mix the chunk index into the last 8 bytes.
  for (var i = 0; i < 8; i++) {
    nonce[11 - i] ^= (index >> (8 * i)) & 0xff;
  }
  return nonce;
}

Uint8List _aad(Uint8List header, int index, {required bool last}) {
  final out = Uint8List(header.length + 9)..setAll(0, header);
  final view = ByteData.sublistView(out);
  view.setUint64(header.length, index);
  out[header.length + 8] = last ? 1 : 0;
  return out;
}

Future<void> _encrypt(_EncryptJob job) async {
  final baseNonce = BackupCrypto.randomBytes(12);
  final header = Uint8List(BackupCrypto.headerLength);
  final view = ByteData.sublistView(header);
  header.setAll(0, BackupCrypto._magic);
  header[4] = BackupCrypto.version;
  view
    ..setUint32(5, job.key.params.memoryKiB)
    ..setUint32(9, job.key.params.iterations);
  header[13] = job.key.params.parallelism;
  header
    ..setAll(14, job.key.salt)
    ..setAll(30, baseNonce);

  final secretKey = SecretKey(job.key.bytes);
  final input = await File(job.input).open();
  final output = File(job.output).openSync(mode: FileMode.write);
  try {
    output.writeFromSync(header);
    final total = await input.length();
    var offset = 0;
    var index = 0;
    // An empty file still gets one (empty) final chunk.
    do {
      final length = min(BackupCrypto.chunkSize, total - offset);
      final plain = length == 0 ? <int>[] : await input.read(length);
      offset += length;
      final last = offset >= total;
      final box = await BackupCrypto._aes.encrypt(
        plain,
        secretKey: secretKey,
        nonce: _nonceFor(baseNonce, index),
        aad: _aad(header, index, last: last),
      );
      final sealed = Uint8List(box.cipherText.length + BackupCrypto.tagLength)
        ..setAll(0, box.cipherText)
        ..setAll(box.cipherText.length, box.mac.bytes);
      final lengthBytes = Uint8List(4);
      ByteData.sublistView(lengthBytes).setUint32(0, sealed.length);
      output
        ..writeFromSync(lengthBytes)
        ..writeFromSync(sealed);
      index++;
      if (last) break;
    } while (true);
  } finally {
    await input.close();
    output.closeSync();
  }
}

Future<void> _decrypt(_DecryptJob job) async {
  final input = File(job.input).openSync();
  IOSink? sink;
  try {
    final headerBytes = input.readSync(BackupCrypto.headerLength);
    final header = BackupHeader.parse(Uint8List.fromList(headerBytes));
    final secretKey = SecretKey(job.key.bytes);
    sink = File(job.output).openWrite();

    final total = input.lengthSync();
    var index = 0;
    while (true) {
      if (input.positionSync() + 4 > total) {
        throw const BackupCryptoException(BackupCryptoError.truncated);
      }
      final lengthBytes = input.readSync(4);
      final sealedLength = ByteData.sublistView(Uint8List.fromList(lengthBytes))
          .getUint32(0);
      if (sealedLength < BackupCrypto.tagLength ||
          sealedLength > BackupCrypto.chunkSize + BackupCrypto.tagLength ||
          input.positionSync() + sealedLength > total) {
        throw const BackupCryptoException(BackupCryptoError.truncated);
      }
      final sealed = Uint8List.fromList(input.readSync(sealedLength));
      final last = input.positionSync() >= total;
      final cipherLength = sealedLength - BackupCrypto.tagLength;
      final box = SecretBox(
        sealed.sublist(0, cipherLength),
        nonce: _nonceFor(header.baseNonce, index),
        mac: Mac(sealed.sublist(cipherLength)),
      );
      List<int> plain;
      try {
        plain = await BackupCrypto._aes.decrypt(
          box,
          secretKey: secretKey,
          aad: _aad(header.raw, index, last: last),
        );
      } on SecretBoxAuthenticationError {
        // Wrong passphrase, a damaged file, or chunks removed from the end
        // (which makes an earlier chunk wrongly look like the last one).
        throw const BackupCryptoException(
          BackupCryptoError.authenticationFailed,
        );
      }
      sink.add(plain);
      index++;
      if (last) break;
    }
    await sink.flush();
  } finally {
    input.closeSync();
    await sink?.close();
  }
}

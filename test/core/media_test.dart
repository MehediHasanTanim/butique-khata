import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/media/image_processor.dart';
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/services/photo_source.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/orders/data/attachment_repository.dart';
import 'package:tailor_khata/features/orders/domain/photo_attachment.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

/// Noisy picture that does not compress well.
Uint8List noisyPng(int width, int height) {
  final random = Random(1);
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Smooth scene with mild noise, like a real photograph.
Uint8List photoLike(int width, int height) {
  final random = Random(2);
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p
      ..r = (p.x * 255 ~/ width + random.nextInt(12)).clamp(0, 255)
      ..g = (p.y * 255 ~/ height + random.nextInt(12)).clamp(0, 255)
      ..b = ((p.x + p.y) % 256 ~/ 2 + random.nextInt(12)).clamp(0, 255);
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('processImage (S3-06)', () {
    test('shrinks a big photo to 1280 px and under 300 KB', () {
      final result = processImage(photoLike(2400, 1800));
      expect(result.width, 1280);
      expect(result.height, 960);
      expect(result.full.length, lessThanOrEqualTo(300 * 1024));
      final decoded = img.decodeJpg(result.full)!;
      expect(decoded.width, 1280);
    });

    test('pure noise is shrunk further to fit, but stays usable', () {
      final result = processImage(noisyPng(2400, 1800));
      expect(result.full.length, lessThanOrEqualTo(300 * 1024));
      expect(result.width, lessThan(1280));
      expect(result.width, greaterThanOrEqualTo(640));
    });

    test('a hopeless size limit stops at the minimum side', () {
      final result = processImage(noisyPng(1000, 750), maxBytes: 1000);
      expect(result.width, greaterThanOrEqualTo(640 * 0.85));
      expect(result.width, lessThan(1000));
    });

    test('portrait photos are limited on the long side too', () {
      final result = processImage(photoLike(900, 2000));
      expect(result.height, 1280);
      expect(result.width, lessThan(1280));
    });

    test('small photos are not enlarged; thumbnail is 200 px', () {
      final result = processImage(samplePng(width: 400, height: 300));
      expect(result.width, 400);
      expect(result.height, 300);
      final thumb = img.decodeJpg(result.thumb)!;
      expect(thumb.width, 200);
      expect(thumb.height, 150);
      expect(result.thumb.length, lessThan(result.full.length));
    });

    test('phone rotation flag is applied so photos are upright', () {
      final image = img.Image(width: 800, height: 600);
      image.exif.imageIfd.orientation = 6; // rotated 90°
      final jpg = Uint8List.fromList(img.encodeJpg(image));
      final result = processImage(jpg);
      expect(result.width, 600);
      expect(result.height, 800);
    });

    test('rejects bytes that are not an image', () {
      expect(
        () => processImage(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('FileMediaStore', () {
    late Directory dir;
    late FileMediaStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tk_store');
      store = FileMediaStore(Directory('${dir.path}/media'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves image and thumbnail under relative paths', () async {
      final stored = await store.saveImage(samplePng());
      expect(stored.path, endsWith('.jpg'));
      expect(stored.thumbPath, endsWith('.thumb.jpg'));
      expect(stored.path.contains('/'), isFalse, reason: 'relative');
      expect(store.resolve(stored.path).existsSync(), isTrue);
      expect(store.resolve(stored.thumbPath).existsSync(), isTrue);
      expect(store.resolve(stored.path).lengthSync(), lessThan(300 * 1024 + 1));
    });

    test('each photo gets its own files', () async {
      final a = await store.saveImage(samplePng());
      final b = await store.saveImage(samplePng());
      expect(a.path, isNot(b.path));
    });

    test('delete removes both files and tolerates missing ones', () async {
      final stored = await store.saveImage(samplePng());
      await store.delete(stored);
      expect(store.resolve(stored.path).existsSync(), isFalse);
      expect(store.resolve(stored.thumbPath).existsSync(), isFalse);
      await store.delete(stored); // no error
    });

    test('a corrupt picture leaves nothing behind', () async {
      await expectLater(
        store.saveImage(Uint8List.fromList([9, 9, 9])),
        throwsA(anything),
      );
      final media = Directory('${dir.path}/media');
      expect(!media.existsSync() || media.listSync().isEmpty, isTrue);
    });
  });

  group('AttachmentRepository', () {
    late AppDatabase db;
    late Directory dir;
    late FileMediaStore store;
    late AttachmentRepository repo;

    setUp(() {
      db = memoryDb();
      dir = Directory.systemTemp.createTempSync('tk_att');
      store = FileMediaStore(Directory('${dir.path}/media'));
      repo = AttachmentRepository(
        db,
        store,
        FixedClock(DateTime(2026, 3, 10)),
        SequentialIdGenerator('a'),
      );
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    test('add, list and watch photos per owner', () async {
      final seen = <int>[];
      final sub = repo
          .watch(AttachmentOwner.orderItem, 'item1')
          .listen((l) => seen.add(l.length));
      await pumpEventQueue();
      final first = await repo.addBytes(
        AttachmentOwner.orderItem,
        'item1',
        samplePng(),
      );
      await repo.addBytes(AttachmentOwner.orderItem, 'item2', samplePng());
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.first, 0);
      expect(seen.last, 1);
      expect(seen.toSet(), {0, 1});
      final list = await repo.list(AttachmentOwner.orderItem, 'item1');
      expect(list.single.id, first.id);
      expect(store.resolve(list.single.image.path).existsSync(), isTrue);
    });

    test('remove deletes the row and the files', () async {
      final photo = await repo.addBytes(
        AttachmentOwner.orderItem,
        'item1',
        samplePng(),
      );
      await repo.remove(photo);
      expect(await repo.list(AttachmentOwner.orderItem, 'item1'), isEmpty);
      expect(store.resolve(photo.image.path).existsSync(), isFalse);
      expect(store.resolve(photo.image.thumbPath).existsSync(), isFalse);
    });

    test('a database failure cleans the new files up', () async {
      // Two repositories handing out the same id make the second insert fail.
      final firstRepo = AttachmentRepository(
        db,
        store,
        FixedClock(DateTime(2026, 3, 10)),
        _FixedId('dup'),
      );
      final secondRepo = AttachmentRepository(
        db,
        store,
        FixedClock(DateTime(2026, 3, 10)),
        _FixedId('dup'),
      );
      await firstRepo.addBytes(AttachmentOwner.orderItem, 'x', samplePng());
      final filesBefore = Directory('${dir.path}/media').listSync().length;
      await expectLater(
        secondRepo.addBytes(AttachmentOwner.orderItem, 'x', samplePng()),
        throwsA(anything),
      );
      expect(Directory('${dir.path}/media').listSync().length, filesBefore);
    });

    test('addFromSource handles cancel and corrupt pictures', () async {
      final source = FakePhotoSource()..cancel = true;
      expect(
        await repo.addFromSource(
          source,
          PhotoOrigin.camera,
          AttachmentOwner.orderItem,
          'item1',
        ),
        isNull,
      );
      source
        ..cancel = false
        ..corrupt = true;
      await expectLater(
        repo.addFromSource(
          source,
          PhotoOrigin.gallery,
          AttachmentOwner.orderItem,
          'item1',
        ),
        throwsFormatException,
      );
      expect(await repo.list(AttachmentOwner.orderItem, 'item1'), isEmpty);
      expect(source.requests, [PhotoOrigin.camera, PhotoOrigin.gallery]);
    });
  });
}

class _FixedId implements IdGenerator {
  _FixedId(this.id);
  final String id;

  @override
  String newId() => id;
}

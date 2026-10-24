import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_khata/features/backup/data/drive_backup_store.dart';

import '../../support/drive_fakes.dart';

void main() {
  late Directory tmp;
  late File backup;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tk_drive');
    addTearDown(() => tmp.deleteSync(recursive: true));
    backup = File('${tmp.path}/tailor_khata_20260310_090000.tkbackup')
      ..writeAsBytesSync(List.generate(5000, (i) => i % 251));
  });

  group('upload', () {
    test('starts a resumable upload into the app-data folder, then sends the bytes', () async {
      final seen = <http.BaseRequest>[];
      List<int>? sentBytes;
      String? metadata;
      final client = MockClient.streaming((request, body) async {
        seen.add(request);
        final bytes = await body.expand((c) => c).toList();
        if (request.method == 'POST') {
          metadata = utf8.decode(bytes);
          return http.StreamedResponse(
            Stream.value(utf8.encode('{}')),
            200,
            headers: {'location': 'https://upload.example/session-1'},
          );
        }
        sentBytes = bytes;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"id":"file-9"}')),
          200,
        );
      });
      final id = await DriveBackupStore(FakeDriveAuth(), client).upload(backup);

      expect(id, 'file-9');
      expect(seen[0].url.path, '/upload/drive/v3/files');
      expect(seen[0].url.queryParameters['uploadType'], 'resumable');
      expect(seen[0].headers['Authorization'], 'Bearer token-1');
      expect(seen[0].headers['X-Upload-Content-Length'], '5000');
      expect(jsonDecode(metadata!), {
        'name': 'tailor_khata_20260310_090000.tkbackup',
        'parents': ['appDataFolder'],
      });
      expect(seen[1].method, 'PUT');
      expect(seen[1].url.toString(), 'https://upload.example/session-1');
      expect(sentBytes, backup.readAsBytesSync());
    });

    test('signed out gives notSignedIn without any request', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 200);
      });
      await expectLater(
        DriveBackupStore(FakeDriveAuth(signedIn: false), client).upload(backup),
        throwsA(
          isA<DriveException>().having(
            (e) => e.error,
            'error',
            DriveError.notSignedIn,
          ),
        ),
      );
      expect(calls, 0);
    });

    test('an expired token (401) is notSignedIn', () async {
      final client = MockClient((_) async => http.Response('nope', 401));
      await expectLater(
        DriveBackupStore(FakeDriveAuth(), client).upload(backup),
        throwsA(
          isA<DriveException>().having(
            (e) => e.error,
            'error',
            DriveError.notSignedIn,
          ),
        ),
      );
    });

    test('no internet is a network error', () async {
      final client = MockClient(
        (_) async => throw const SocketException('offline'),
      );
      await expectLater(
        DriveBackupStore(FakeDriveAuth(), client).upload(backup),
        throwsA(
          isA<DriveException>().having(
            (e) => e.error,
            'error',
            DriveError.network,
          ),
        ),
      );
    });

    test(
      'a server error is a network error, a client error is rejected',
      () async {
        for (final (status, expected) in [
          (503, DriveError.network),
          (400, DriveError.rejected),
        ]) {
          final client = MockClient((_) async => http.Response('x', status));
          await expectLater(
            DriveBackupStore(FakeDriveAuth(), client).upload(backup),
            throwsA(
              isA<DriveException>().having((e) => e.error, 'error', expected),
            ),
          );
        }
      },
    );
  });

  group('list and download', () {
    test(
      'lists only backup files, newest first as Drive returns them',
      () async {
        late Uri requested;
        final client = MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'a',
                  'name': 'x.tkbackup',
                  'modifiedTime': '2026-03-10T09:00:00.000Z',
                  'size': '1234',
                },
                {
                  'id': 'b',
                  'name': 'notes.txt',
                  'modifiedTime': '2026-03-09T09:00:00.000Z',
                  'size': '5',
                },
              ],
            }),
            200,
          );
        });
        final list = await DriveBackupStore(FakeDriveAuth(), client).list();
        expect(requested.queryParameters['spaces'], 'appDataFolder');
        expect(list.map((b) => b.id), ['a']);
        expect(list.single.sizeBytes, 1234);
        expect(list.single.modified.toUtc(), DateTime.utc(2026, 3, 10, 9));
      },
    );

    test('an empty Drive lists nothing', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      expect(await DriveBackupStore(FakeDriveAuth(), client).list(), isEmpty);
    });

    test('downloads the bytes into a file', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/drive/v3/files/abc');
        expect(request.url.queryParameters['alt'], 'media');
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final target = File('${tmp.path}/got.tkbackup');
      await DriveBackupStore(FakeDriveAuth(), client).download('abc', target);
      expect(target.readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('a failed download leaves no half file', () async {
      final client = MockClient((_) async => http.Response('gone', 404));
      final target = File('${tmp.path}/got.tkbackup');
      await expectLater(
        DriveBackupStore(FakeDriveAuth(), client).download('abc', target),
        throwsA(isA<DriveException>()),
      );
      expect(target.existsSync(), isFalse);
    });
  });

  group('tidying up', () {
    test('keeps the newest five and deletes the rest', () async {
      final deleted = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted.add(request.url.pathSegments.last);
          return http.Response('', 204);
        }
        return http.Response(
          jsonEncode({
            'files': [
              for (var i = 0; i < 8; i++)
                {
                  'id': 'f$i',
                  'name': 'b$i.tkbackup',
                  'modifiedTime': '2026-03-0${9 - i}T09:00:00Z',
                  'size': '1',
                },
            ],
          }),
          200,
        );
      });
      await DriveBackupStore(FakeDriveAuth(), client).prune();
      expect(deleted, ['f5', 'f6', 'f7']);
    });

    test('a failure while tidying is swallowed', () async {
      final client = MockClient(
        (_) async => throw const SocketException('offline'),
      );
      await DriveBackupStore(FakeDriveAuth(), client).prune();
    });
  });
}

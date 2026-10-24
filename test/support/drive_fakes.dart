import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tailor_khata/features/backup/data/drive_auth.dart';
import 'package:tailor_khata/features/backup/data/drive_backup_store.dart';

class FakeDriveAuth implements DriveAuth {
  FakeDriveAuth({this.signedIn = true});

  bool signedIn;
  bool signedOut = false;
  final List<bool> interactiveCalls = [];

  @override
  Future<Map<String, String>?> headers({bool interactive = false}) async {
    interactiveCalls.add(interactive);
    return signedIn ? {'Authorization': 'Bearer token-1'} : null;
  }

  @override
  Future<String?> email() async => signedIn ? 'me@example.com' : null;

  @override
  Future<void> signOut() async {
    signedOut = true;
    signedIn = false;
  }
}

/// A Google Drive app-data folder kept in memory, speaking the REST calls the
/// app makes.
class FakeDrive {
  /// id -> (name, bytes, modified)
  final Map<String, ({String name, List<int> bytes, DateTime modified})> files =
      {};
  bool offline = false;
  int _next = 1;
  String? _pendingName;

  late final http.Client client = MockClient.streaming((request, body) async {
    if (offline) throw const SocketException('offline');
    final bytes = await body.expand((c) => c).toList();
    final path = request.url.path;
    http.StreamedResponse reply(
      int status,
      List<int> data, [
      Map<String, String>? headers,
    ]) => http.StreamedResponse(
      Stream.value(data),
      status,
      headers: headers ?? {},
    );

    if (request.method == 'POST' && path == '/upload/drive/v3/files') {
      _pendingName =
          (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['name']
              as String;
      return reply(200, utf8.encode('{}'), {
        'location': 'https://upload.fake/session',
      });
    }
    if (request.method == 'PUT' && request.url.host == 'upload.fake') {
      final id = 'file-${_next++}';
      files[id] = (name: _pendingName!, bytes: bytes, modified: DateTime.now());
      return reply(200, utf8.encode('{"id":"$id"}'));
    }
    if (request.method == 'GET' && path == '/drive/v3/files') {
      final sorted = files.entries.toList()
        ..sort((a, b) => b.value.modified.compareTo(a.value.modified));
      return reply(
        200,
        utf8.encode(
          jsonEncode({
            'files': [
              for (final e in sorted)
                {
                  'id': e.key,
                  'name': e.value.name,
                  'modifiedTime': e.value.modified.toUtc().toIso8601String(),
                  'size': '${e.value.bytes.length}',
                },
            ],
          }),
        ),
      );
    }
    if (request.method == 'GET' && path.startsWith('/drive/v3/files/')) {
      final file = files[request.url.pathSegments.last];
      return file == null ? reply(404, []) : reply(200, file.bytes);
    }
    if (request.method == 'DELETE') {
      files.remove(request.url.pathSegments.last);
      return reply(204, []);
    }
    return reply(400, []);
  });

  DriveBackupStore store(DriveAuth auth) => DriveBackupStore(auth, client);
}

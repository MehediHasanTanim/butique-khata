import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tailor_khata/features/backup/data/drive_auth.dart';

/// Why a Google Drive call did not work.
enum DriveError { notSignedIn, network, rejected }

class DriveException implements Exception {
  const DriveException(this.error, [this.detail]);

  final DriveError error;
  final String? detail;

  @override
  String toString() => 'DriveException($error, $detail)';
}

/// A backup stored in Drive's hidden app-data folder.
class DriveBackup {
  const DriveBackup({
    required this.id,
    required this.name,
    required this.modified,
    required this.sizeBytes,
  });

  final String id;
  final String name;
  final DateTime modified;
  final int sizeBytes;
}

/// Backups in the app's private Drive folder (`appDataFolder`): invisible in
/// the Drive app, removed when the app's data is, and unreadable to other
/// apps. The files are already encrypted, so Google only ever holds noise.
class DriveBackupStore {
  DriveBackupStore(this._auth, [http.Client? client])
    : _client = client ?? http.Client();

  final DriveAuth _auth;
  final http.Client _client;

  static const String _api = 'https://www.googleapis.com/drive/v3/files';
  static const String _upload =
      'https://www.googleapis.com/upload/drive/v3/files';

  Future<Map<String, String>> _headers(bool interactive) async {
    final headers = await _auth.headers(interactive: interactive);
    if (headers == null) throw const DriveException(DriveError.notSignedIn);
    return headers;
  }

  /// Runs [call], turning transport failures and error responses into
  /// [DriveException]s.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DriveException {
      rethrow;
    } on SocketException catch (e) {
      throw DriveException(DriveError.network, e.message);
    } on http.ClientException catch (e) {
      throw DriveException(DriveError.network, e.message);
    } on HttpException catch (e) {
      throw DriveException(DriveError.network, e.message);
    }
  }

  void _check(http.BaseResponse response, [String? body]) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw DriveException(DriveError.notSignedIn, body);
    }
    if (response.statusCode >= 500) {
      throw DriveException(DriveError.network, '${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DriveException(DriveError.rejected, '${response.statusCode} $body');
    }
  }

  /// Backups in Drive, newest first.
  Future<List<DriveBackup>> list({bool interactive = false}) =>
      _guard(() async {
        final headers = await _headers(interactive);
        final uri = Uri.parse(_api).replace(
          queryParameters: {
            'spaces': 'appDataFolder',
            'orderBy': 'modifiedTime desc',
            'pageSize': '100',
            'fields': 'files(id,name,modifiedTime,size)',
          },
        );
        final response = await _client.get(uri, headers: headers);
        _check(response, response.body);
        final files =
            (jsonDecode(response.body) as Map<String, dynamic>)['files'];
        return [
          for (final f in (files as List<dynamic>? ?? const []))
            if ((f as Map<String, dynamic>)['name'].toString().endsWith(
              '.tkbackup',
            ))
              DriveBackup(
                id: f['id'] as String,
                name: f['name'] as String,
                modified: DateTime.parse(f['modifiedTime'] as String).toLocal(),
                sizeBytes: int.tryParse('${f['size']}') ?? 0,
              ),
        ];
      });

  /// Uploads [file] (resumable, streamed, so a large backup is never held in
  /// memory) and returns its Drive id.
  Future<String> upload(
    File file, {
    bool interactive = false,
  }) => _guard(() async {
    final headers = await _headers(interactive);
    final name = file.uri.pathSegments.last;
    final length = await file.length();

    final start =
        http.Request(
            'POST',
            Uri.parse(_upload).replace(
              queryParameters: {'uploadType': 'resumable', 'fields': 'id'},
            ),
          )
          ..headers.addAll({
            ...headers,
            'Content-Type': 'application/json; charset=UTF-8',
            'X-Upload-Content-Type': 'application/octet-stream',
            'X-Upload-Content-Length': '$length',
          })
          ..body = jsonEncode({
            'name': name,
            'parents': ['appDataFolder'],
          });
    final started = await http.Response.fromStream(await _client.send(start));
    _check(started, started.body);
    final location = started.headers['location'];
    if (location == null) {
      throw const DriveException(DriveError.rejected, 'no upload location');
    }

    final put = http.StreamedRequest('PUT', Uri.parse(location))
      ..headers.addAll({...headers, 'Content-Type': 'application/octet-stream'})
      ..contentLength = length;
    file.openRead().listen(
      put.sink.add,
      onError: put.sink.addError,
      onDone: put.sink.close,
      cancelOnError: true,
    );
    final done = await http.Response.fromStream(await _client.send(put));
    _check(done, done.body);
    return (jsonDecode(done.body) as Map<String, dynamic>)['id'] as String;
  });

  /// Downloads backup [id] into [target].
  Future<void> download(String id, File target, {bool interactive = false}) =>
      _guard(() async {
        final headers = await _headers(interactive);
        final request = http.Request(
          'GET',
          Uri.parse('$_api/$id').replace(queryParameters: {'alt': 'media'}),
        )..headers.addAll(headers);
        final response = await _client.send(request);
        _check(response);
        final sink = target.openWrite();
        try {
          await response.stream.pipe(sink);
        } on Object {
          if (target.existsSync()) target.deleteSync();
          rethrow;
        }
      });

  Future<void> delete(String id) => _guard(() async {
    final response = await _client.delete(
      Uri.parse('$_api/$id'),
      headers: await _headers(false),
    );
    if (response.statusCode != 404) _check(response, response.body);
  });

  /// Keeps the newest [keep] backups in Drive and removes the rest. A failure
  /// to tidy up is never worth failing a backup over.
  Future<void> prune({int keep = 5}) async {
    try {
      final all = await list();
      for (final old in all.skip(keep)) {
        await delete(old.id);
      }
    } on DriveException {
      // Left for next time.
    }
  }
}

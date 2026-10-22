import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tailor_khata/core/media/media_store.dart';
import 'package:tailor_khata/core/services/external_launcher.dart';
import 'package:tailor_khata/core/services/file_sharer.dart';
import 'package:tailor_khata/core/services/notification_service.dart';
import 'package:tailor_khata/core/services/photo_source.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:tailor_khata/features/settings/data/app_settings.dart';

/// Records every schedule and lets a test simulate taps and permissions.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({this.granted = false, this.launch});

  bool granted;
  String? launch;
  final List<List<PlannedNotification>> schedules = [];
  final StreamController<String> _taps = StreamController<String>.broadcast();
  int permissionRequests = 0;

  List<PlannedNotification> get current =>
      schedules.isEmpty ? const [] : schedules.last;

  void tap(String payload) => _taps.add(payload);

  @override
  Future<void> init() async {}

  @override
  String? get launchPayload => launch;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<bool> arePermissionsGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    granted = true;
    return true;
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> notifications) async {
    schedules.add(List.of(notifications));
  }
}

class FakeLauncher implements ExternalLauncher {
  FakeLauncher({this.succeeds = true});

  bool succeeds;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}

class FakeSharer implements FileSharer {
  final List<({Uint8List bytes, String fileName})> shared = [];

  @override
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async {
    shared.add((bytes: bytes, fileName: fileName));
  }
}

/// Hands out generated pictures, or null to simulate cancelling.
class FakePhotoSource implements PhotoSource {
  final List<PhotoOrigin> requests = [];
  bool cancel = false;
  bool corrupt = false;

  @override
  Future<Uint8List?> pick(PhotoOrigin origin) async {
    requests.add(origin);
    if (cancel) return null;
    if (corrupt) return Uint8List.fromList([1, 2, 3, 4]);
    return samplePng();
  }
}

/// A small valid PNG (a gradient so it is not trivially compressible).
Uint8List samplePng({int width = 640, int height = 480}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = pixel.x * 255 ~/ width
      ..g = pixel.y * 255 ~/ height
      ..b = (pixel.x + pixel.y) % 256;
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Everything a test may want to inspect or tweak.
class TestEnv {
  TestEnv({DateTime? now, bool notificationsGranted = false, String? launch})
    : clock = FixedClock(now ?? DateTime(2026, 3, 10, 10)),
      notifications = FakeNotificationService(
        granted: notificationsGranted,
        launch: launch,
      ),
      dir = Directory.systemTemp.createTempSync('tk_media') {
    media = FileMediaStore(Directory('${dir.path}/media'));
  }

  final FixedClock clock;

  /// Settings the app starts with.
  AppSettings settings = const AppSettings();
  final FakeNotificationService notifications;
  final FakeLauncher launcher = FakeLauncher();
  final FakeSharer sharer = FakeSharer();
  final FakePhotoSource photos = FakePhotoSource();
  final Directory dir;
  late final FileMediaStore media;

  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

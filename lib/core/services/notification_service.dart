import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tailor_khata/core/logging/app_log.dart';
import 'package:tailor_khata/features/deliveries/domain/reminder_planner.dart';
import 'package:timezone/timezone.dart' as tz;

/// Local (offline) notifications, behind an interface so reminder logic can
/// be tested without a phone (D-2).
abstract class NotificationService {
  /// One-time setup; call before anything else.
  Future<void> init();

  /// Route of the notification that launched the app, if any.
  String? get launchPayload;

  /// Routes of notifications tapped while the app is running.
  Stream<String> get taps;

  /// True if the system lets us show notifications.
  Future<bool> arePermissionsGranted();

  /// Asks the user (Android 13+, iOS). Returns the resulting state.
  Future<bool> requestPermission();

  /// Makes the pending notifications exactly [notifications]. Anything
  /// scheduled before is removed first.
  Future<void> replaceAll(List<PlannedNotification> notifications);
}

/// Does nothing; used on platforms without notification support.
class NoopNotificationService implements NotificationService {
  @override
  Future<void> init() async {}

  @override
  String? get launchPayload => null;

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<bool> arePermissionsGranted() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(List<PlannedNotification> notifications) async {}
}

/// `flutter_local_notifications` implementation. Notifications are scheduled
/// with inexact alarms so no special permission is needed; they may arrive a
/// few minutes late on a phone in battery saver, which is fine for reminders.
class LocalNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();
  String? _launchPayload;

  static const _channelId = 'deliveries';
  static const _androidDetails = AndroidNotificationDetails(
    _channelId,
    'Delivery reminders',
    channelDescription: 'Reminders about garments due for delivery',
    importance: Importance.high,
    priority: Priority.high,
  );

  @override
  String? get launchPayload => _launchPayload;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _taps.add(payload);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchPayload = launch?.notificationResponse?.payload;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> arePermissionsGranted() async {
    final android = _android;
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _ios;
    if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    final android = _android;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _ios;
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  /// Fixed-offset zone for the device's current offset. Bangladesh has no
  /// daylight saving; elsewhere the schedule is rebuilt on every app start so
  /// an offset change is picked up quickly.
  tz.Location _deviceZone() {
    final offset = DateTime.now().timeZoneOffset.inMilliseconds;
    return tz.Location('device', [-8640000000000000], [0], [
      tz.TimeZone(
        Duration(milliseconds: offset),
        isDst: false,
        abbreviation: 'local',
      ),
    ]);
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> notifications) async {
    try {
      await _plugin.cancelAllPendingNotifications();
      final zone = _deviceZone();
      for (final n in notifications) {
        final when = tz.TZDateTime.from(n.at, zone);
        final android = _android;
        if (android != null) {
          await android.zonedSchedule(
            id: n.id,
            title: n.title,
            body: n.body,
            scheduledDate: when,
            payload: n.payload,
            notificationDetails: _androidDetails,
            scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        } else {
          await _ios?.zonedSchedule(
            id: n.id,
            title: n.title,
            body: n.body,
            scheduledDate: when,
            payload: n.payload,
          );
        }
      }
    } on Object catch (error) {
      // Reminders are a convenience; the dashboard stays the source of truth.
      AppLog.e('reminders', 'Scheduling failed', error);
      if (kDebugMode) rethrow;
    }
  }
}

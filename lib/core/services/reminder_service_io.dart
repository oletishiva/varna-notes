import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app_config.dart';
import 'reminder_service.dart';

/// Reminders on Android/iOS; a no-op elsewhere (desktop).
ReminderService createReminderService() {
  if (Platform.isAndroid || Platform.isIOS) {
    return LocalNotificationsReminderService();
  }
  return const NoopReminderService();
}

/// Called when the user taps a reminder notification. Opening the card needs
/// the app's router, which this service has no access to, so this does
/// nothing on purpose: the tap simply brings the app forward (the system does
/// that) and the user finds the card in Reminders.
void _onReminderTapped(NotificationResponse response) {}

/// flutter_local_notifications based reminders.
///
/// Notifications are scheduled for an absolute instant (converted to UTC),
/// so the device time zone does not need to be known. Android uses inexact
/// scheduling, so no exact-alarm permission is required (the reminder can be
/// a few minutes late when the device is dozing).
class LocalNotificationsReminderService implements ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  Future<void> _ensureInitialised() async {
    if (_initialised) {
      return;
    }
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onReminderTapped,
    );
    _initialised = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) {
      return false;
    }
    await _ensureInitialised();
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final IOSFlutterLocalNotificationsPlugin? ios =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  @override
  Future<void> schedule({
    required String cardId,
    required String title,
    String? body,
    required DateTime when,
  }) async {
    if (!isSupported) {
      return;
    }
    await _ensureInitialised();
    final DateTime instant = when.toUtc();
    if (!instant.isAfter(DateTime.now().toUtc())) {
      return;
    }
    await _plugin.zonedSchedule(
      id: reminderNotificationId(cardId),
      scheduledDate: tz.TZDateTime.from(instant, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'varna_reminders',
          'Reminders',
          channelDescription: '${AppConfig.appName} card and renewal reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      payload: cardId,
    );
  }

  @override
  Future<void> cancel(String cardId) async {
    if (!isSupported) {
      return;
    }
    await _ensureInitialised();
    await _plugin.cancel(id: reminderNotificationId(cardId));
  }
}

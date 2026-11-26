import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../utils/minido_helpers.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initialization;

  bool get _isSupported =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.macOS => true,
        _ => false,
      };

  Future<void> init() {
    if (!_isSupported || _initialized) return Future<void>.value();
    return _initialization ??= _initializeSupportedPlatform();
  }

  Future<void> _initializeSupportedPlatform() async {
    try {
      timezone_data.initializeTimeZones();
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      if (initialized == false) {
        throw StateError('The local notification plugin did not initialize.');
      }
      _initialized = true;
    } catch (error, stackTrace) {
      _initialization = null;
      debugPrint('Could not initialize local reminders: $error\n$stackTrace');
    }
  }

  Future<bool> requestPermissions() async {
    if (!_isSupported) return false;
    await init();
    if (!_initialized) return false;

    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.requestNotificationsPermission() ??
              false;
        case TargetPlatform.iOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, badge: true, sound: true) ??
              false;
        case TargetPlatform.macOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, badge: true, sound: true) ??
              false;
        default:
          return false;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Could not request notification permissions: $error\n$stackTrace',
      );
      return false;
    }
  }

  Future<void> cancelTaskReminders(String taskId) async {
    if (!_isSupported) return;
    await init();
    if (!_initialized) return;

    try {
      final baseId = _baseId(taskId);
      for (var index = 0; index < 3; index++) {
        await _plugin.cancel(id: baseId + index);
      }
    } catch (error, stackTrace) {
      debugPrint('Could not cancel reminders for $taskId: $error\n$stackTrace');
    }
  }

  Future<void> scheduleTaskReminders({
    required String taskId,
    required String title,
    required DateTime? dueDate,
    required bool isCompleted,
    required bool isCancelled,
    int? reminderOffsetMinutes,
  }) async {
    if (!_isSupported) return;
    await init();
    if (!_initialized) return;

    final baseId = _baseId(taskId);
    try {
      for (var index = 0; index < 3; index++) {
        await _plugin.cancel(id: baseId + index);
      }

      if (kIsWeb || dueDate == null || isCompleted || isCancelled) {
        return;
      }

      final offset = reminderOffsetMinutes ?? 15;
      if (offset < 0) return;

      final now = DateTime.now();
      final dueTime = dueDate.toLocal();
      final reminders = <(DateTime, String)>[];
      if (offset >= 0) {
        reminders.add((dueTime, 'Due now: $title'));
      }
      if (offset > 0) {
        reminders.add((
          dueTime.subtract(Duration(minutes: offset)),
          '${MinidoReminder.labelFor(offset)}: $title',
        ));
      }

      var notificationIndex = 0;
      for (var index = 0; index < reminders.length; index++) {
        final (scheduledAt, notificationTitle) = reminders[index];
        if (!scheduledAt.isAfter(now)) continue;

        await _plugin.zonedSchedule(
          id: baseId + notificationIndex,
          title: notificationTitle,
          body: '',
          scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'minido_task_reminders',
              'Task reminders',
              channelDescription: 'Due date reminders for Minido tasks',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        notificationIndex++;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Could not schedule reminders for $taskId: $error\n$stackTrace',
      );
    }
  }

  int _baseId(String taskId) => taskId.hashCode.abs() % 100000000;
}

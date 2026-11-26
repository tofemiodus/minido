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
      try {
        final timezone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timezone.identifier));
      } catch (error) {
        final localOffset = DateTime.now().timeZoneOffset;
        tz.Location? matchingLocation;
        for (final location in tz.timeZoneDatabase.locations.values) {
          if (location.currentTimeZone.offset == localOffset) {
            matchingLocation = location;
            break;
          }
        }
        if (matchingLocation == null) {
          throw StateError(
            'Could not match the device time zone offset $localOffset: $error',
          );
        }
        tz.setLocalLocation(matchingLocation);
        debugPrint(
          'Could not read the device time zone; using ${matchingLocation.name} '
          'for its current UTC offset.',
        );
      }
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

      final reminders = <(DateTime, String)>[];
      if (offset >= 0) {
        reminders.add((dueDate, 'Due now: $title'));
      }
      if (offset > 0) {
        reminders.add((
          dueDate.subtract(Duration(minutes: offset)),
          '${MinidoReminder.labelFor(offset)}: $title',
        ));
      }

      var notificationIndex = 0;
      for (var index = 0; index < reminders.length; index++) {
        final (targetDateTime, notificationTitle) = reminders[index];
        final scheduledAt = tz.TZDateTime.from(targetDateTime, tz.local);
        if (!scheduledAt.isAfter(tz.TZDateTime.now(tz.local))) continue;

        await _plugin.zonedSchedule(
          id: baseId + notificationIndex,
          title: notificationTitle,
          body: '',
          scheduledDate: scheduledAt,
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

  Future<void> sendTestNotificationIn5Seconds({
    void Function(String message)? onMessage,
  }) async {
    if (!_isSupported) {
      final message = kIsWeb
          ? 'Local test reminders are unavailable in the web app. Use Minido on Android, iOS, or macOS.'
          : 'Local test reminders are not supported on this device.';
      if (onMessage != null) {
        onMessage(message);
      } else {
        debugPrint(message);
      }
      return;
    }

    await init();
    if (!_initialized) {
      const message = 'Could not initialize local reminders on this device.';
      if (onMessage != null) {
        onMessage(message);
      } else {
        debugPrint(message);
      }
      return;
    }

    try {
      await _plugin.zonedSchedule(
        id: 999999999,
        title: 'Minido test reminder',
        body: 'Your local notifications are working.',
        scheduledDate: tz.TZDateTime.now(
          tz.local,
        ).add(const Duration(seconds: 5)),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'minido_test_reminders',
            'Minido test reminders',
            channelDescription: 'Test local notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      onMessage?.call('Test reminder scheduled for 5 seconds from now.');
    } catch (error, stackTrace) {
      debugPrint('Could not schedule test reminder: $error\n$stackTrace');
      onMessage?.call('Could not schedule the test reminder: $error');
    }
  }

  int _baseId(String taskId) => taskId.hashCode.abs() % 100000000;
}

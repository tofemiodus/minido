import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/task_models.dart' hide Priority;
import '../utils/minido_helpers.dart';
// ─── Alert event (Layer A stream) ───────────────────────────────────────────

class AlertEvent {
  const AlertEvent({
    required this.taskId,
    required this.title,
    required this.dueAt,
  });
  final String taskId;
  final String title;
  final DateTime dueAt;
}

// ─── NotificationService ─────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Layer A: stream of alert events fired by the foreground watcher.
  final _alertController = StreamController<AlertEvent>.broadcast();
  Stream<AlertEvent> get onAlert => _alertController.stream;

  // Deduplication set: "<taskId>_<offsetMinutes>_<dueAtIso>"
  final Set<String> _firedAlerts = {};

  // Tasks tracked for Layer A watcher.
  List<TodoTask> _trackedTasks = const [];

  // Layer A periodic timer.
  Timer? _watcherTimer;

  bool _initialized = false;
  Future<void>? _initialization;

  // ── Platform detection ────────────────────────────────────────────────────

  /// True on platforms that support flutter_local_notifications background
  /// scheduling (Layer B): Android, iOS, macOS (non-web only).
  bool get _supportsLayerB =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// True on platforms where flutter_local_notifications can show foreground
  /// notifications at all (Layer A instant show): non-web only.
  bool get _supportsInstantShow => !kIsWeb;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() {
    _startForegroundWatcher();
    if (!_supportsLayerB || _initialized) return Future<void>.value();
    return _initialization ??= _initPlugin();
  }

  Future<void> _initPlugin() async {
    try {
      timezone_data.initializeTimeZones();
      try {
        final tzInfo = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
      } catch (e) {
        final offset = DateTime.now().timeZoneOffset;
        tz.Location? match;
        for (final loc in tz.timeZoneDatabase.locations.values) {
          if (loc.currentTimeZone.offset == offset) {
            match = loc;
            break;
          }
        }
        if (match == null) {
          throw StateError('Could not match timezone offset $offset: $e');
        }
        tz.setLocalLocation(match);
        debugPrint('Timezone fallback: ${match.name}');
      }

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
      );

      final ok = await _plugin.initialize(settings: initSettings);
      if (ok == false) throw StateError('Plugin did not initialize.');

      // Create the high-importance channel on Android.
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
              ?.createNotificationChannel(
                const AndroidNotificationChannel(
                  'minido_reminders',
                  'Minido Reminders',
                  importance: Importance.max,
                  playSound: true,
                  enableVibration: true,
                ),
              );
        } catch (e) {
          debugPrint('Could not create Android notification channel: $e');
        }
      }

      _initialized = true;
    } catch (e, st) {
      _initialization = null;
      debugPrint('Could not init notification plugin: $e\n$st');
    }
  }

  // ── Layer A: Universal foreground watcher ─────────────────────────────────

  void _startForegroundWatcher() {
    _watcherTimer?.cancel();
    _watcherTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => checkDueNow(),
    );
  }

  /// Call on AppLifecycleState.resumed and from the periodic timer.
  void checkDueNow() {
    final now = DateTime.now();
    for (final task in _trackedTasks) {
      if (task.isCompleted || task.isCancelled) continue;
      final due = task.dueAt;
      if (due == null) continue;

      final offset = task.reminderOffsetMinutes;
      final alertTimes = <(DateTime, int)>[
        (due, 0),
        if (offset > 0) (due.subtract(Duration(minutes: offset)), offset),
      ];

      for (final (alertAt, offsetMin) in alertTimes) {
        // Fire if we're within a 15-second window past the alert time.
        if (now.isBefore(alertAt)) continue;
        if (now.difference(alertAt).inSeconds > 15) continue;

        final key = '${task.id}_${offsetMin}_${due.toIso8601String()}';
        if (_firedAlerts.contains(key)) continue;
        _firedAlerts.add(key);

        _fireLayerA(task.id, task.title, due);
      }
    }
  }

  void _fireLayerA(String taskId, String title, DateTime dueAt) {
    // Instant OS notification (non-web platforms only).
    if (_supportsInstantShow) {
      _showInstant(taskId, title);
    }

    // Sound + haptic feedback (best-effort on all platforms).
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // Emit alert event so the UI can show a banner.
    _alertController.add(AlertEvent(taskId: taskId, title: title, dueAt: dueAt));
  }

  Future<void> _showInstant(String taskId, String title) async {
    try {
      await _plugin.show(
        id: taskId.hashCode.abs() % 100000000,
        title: title,
        body: 'Task is due now',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'minido_reminders',
            'Minido Reminders',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Could not show instant notification: $e');
    }
  }

  // ── Sync tasks (Layer A + Layer B) ───────────────────────────────────────

  Future<void> syncTasks(List<TodoTask> tasks) async {
    _trackedTasks = tasks;
    if (!_supportsLayerB) return;
    await init();
    if (!_initialized) return;

    for (final task in tasks) {
      await scheduleTaskReminders(
        taskId: task.id,
        title: task.title,
        dueDate: task.dueAt,
        isCompleted: task.isCompleted,
        isCancelled: task.isCancelled,
        reminderOffsetMinutes: task.reminderOffsetMinutes,
      );
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    if (!_supportsLayerB) return false;
    await init();
    if (!_initialized) return false;

    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (Platform.isMacOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (e, st) {
      debugPrint('Could not request permissions: $e\n$st');
    }
    return false;
  }

  // ── Layer B: Schedule / cancel reminders ─────────────────────────────────

  Future<void> cancelTaskReminders(String taskId) async {
    if (!_supportsLayerB) return;
    await init();
    if (!_initialized) return;

    try {
      final base = _baseId(taskId);
      for (var i = 0; i < 3; i++) {
        await _plugin.cancel(id: base + i);
      }
    } catch (e, st) {
      debugPrint('Could not cancel reminders for $taskId: $e\n$st');
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
    if (!_supportsLayerB) return;
    await init();
    if (!_initialized) return;

    final base = _baseId(taskId);
    try {
      for (var i = 0; i < 3; i++) {
        await _plugin.cancel(id: base + i);
      }
      if (dueDate == null || isCompleted || isCancelled) return;

      final offset = reminderOffsetMinutes ?? 15;
      if (offset < 0) return;

      final reminders = <(DateTime, String)>[
        (dueDate, 'Due now: $title'),
        if (offset > 0)
          (
            dueDate.subtract(Duration(minutes: offset)),
            '${MinidoReminder.labelFor(offset)}: $title',
          ),
      ];

      var idx = 0;
      for (final (at, notifTitle) in reminders) {
        final scheduled = tz.TZDateTime.from(at, tz.local);
        if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) continue;

        // Layer B: only on Android / iOS / macOS.
        await _plugin.zonedSchedule(
          id: base + idx,
          title: notifTitle,
          body: '',
          scheduledDate: scheduled,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'minido_reminders',
              'Minido Reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        idx++;
      }
    } catch (e, st) {
      debugPrint('Could not schedule reminders for $taskId: $e\n$st');
    }
  }

  // ── Test reminder ─────────────────────────────────────────────────────────

  /// Returns a user-visible status string.
  Future<String> triggerTestReminder() async {
    try {
      // Instant alert via Layer A.
      _fireLayerA(
        'test-reminder',
        'Minido test reminder',
        DateTime.now().add(const Duration(seconds: 5)),
      );

      // Also schedule a background notification in 5 s (Layer B if supported).
      if (_supportsLayerB) {
        await init();
        if (_initialized) {
          await _plugin.zonedSchedule(
            id: 999999999,
            title: 'Minido test reminder',
            body: 'Your local notifications are working.',
            scheduledDate: tz.TZDateTime.now(tz.local)
                .add(const Duration(seconds: 5)),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'minido_reminders',
                'Minido Reminders',
                importance: Importance.max,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
              macOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
      return 'Test alert sent (instant + 5s)';
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Legacy helper kept for backward compatibility with main.dart callers.
  Future<void> sendTestNotificationIn5Seconds({
    void Function(String message)? onMessage,
  }) async {
    final result = await triggerTestReminder();
    onMessage?.call(result);
  }

  int _baseId(String taskId) => taskId.hashCode.abs() % 100000000;
}

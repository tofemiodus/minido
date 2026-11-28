import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'models/task_models.dart';
import 'data/task_store.dart';
import 'services/notification_service.dart';
import 'services/pwa_install.dart';
import 'utils/minido_helpers.dart';
import 'utils/quick_parse.dart';

part 'src/views/task_views.dart';
part 'src/views/statistics_view.dart';
part 'src/dialogs/task_editor.dart';
part 'src/dialogs/import_dialog.dart';

void main() => runApp(const MinidoApp());

class MinidoApp extends StatefulWidget {
  const MinidoApp({super.key, this.store});

  final TaskStore? store;

  @override
  State<MinidoApp> createState() => _MinidoAppState();
}

class _MinidoAppState extends State<MinidoApp> with WidgetsBindingObserver {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _quickAddFocus = FocusNode();
  final _quickAddController = TextEditingController();
  late final TaskStore _store = widget.store ?? SharedPreferencesTaskStore();
  final _notificationService = NotificationService.instance;
  VoidCallback? _removeInstallPromptListener;

  List<TodoTask> _tasks = const [];
  ThemeMode _themeMode = ThemeMode.light;
  // v2.2.0: 'warm' | 'oled' curated themes (stored alongside ThemeMode)
  String _craftTheme = 'warm'; // 'warm' | 'oled'
  Priority? _priorityFilter;
  final Set<String> _tagFilters = {};
  String _search = '';
  String _loadError = '';
  bool _isLoading = true;
  bool _isIosSafari = false;
  bool _storagePersisted = false;
  bool _dismissedInstallBanner = false;
  bool _isFirstLaunch = false;
  bool _dismissedWelcomeCard = false;
  bool _isSaving = false;
  int _pendingWrites = 0;
  Future<void> _writeQueue = Future<void>.value();
  String _viewMode = 'list'; // 'list' | 'kanban' | 'cancelled' | 'statistics'
  int _statisticsPeriodDays = 7;
  DateTime? _dueAt;
  bool _parsedDateCleared = false;
  int _quickReminderOffsetMinutes = 15;
  DateTime? _lastExported;
  // v2.2.0: Morning Rollover dismissed flag.
  bool _dismissedRollover = false;
  // v2.2.0: active due-reminder alert banner.
  AlertEvent? _activeAlert;
  StreamSubscription<AlertEvent>? _alertSub;

  QuickAddDraft get _quickDraft => parseQuickAdd(_quickAddController.text);

  // v2.2.0: live quick-parse preview — only shown when user has NOT cleared it.
  QuickParseResult? get _liveParseResult {
    if (_parsedDateCleared) return null;
    final raw = _quickAddController.text;
    if (raw.trim().isEmpty) return null;
    final result = quickParse(raw);
    return result.hasDate ? result : null;
  }

  // v2.2.0: tasks from before today that are still active (morning rollover).
  List<TodoTask> get _rolloverTasks {
    final todayMidnight = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return _tasks.where((t) {
      if (t.isCompleted || t.isCancelled) return false;
      // Use updatedAt as a proxy for when the task was last modified.
      return t.updatedAt.toLocal().isBefore(todayMidnight);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_notificationService.init());
    unawaited(_requestMobileNotificationPermissions());
    // v2.2.0: subscribe to Layer A alert events for in-app banner.
    _alertSub = _notificationService.onAlert.listen((event) {
      if (!mounted) return;
      setState(() => _activeAlert = event);
    });
    if (kIsWeb) {
      _removeInstallPromptListener = listenForInstallPrompt((eventType) {
        if (!mounted) return;
        setState(() {
          if (eventType == 'minido-app-installed') {
            _dismissedInstallBanner = true;
          }
        });
      });
    }
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quickAddFocus.dispose();
    _quickAddController.dispose();
    _removeInstallPromptListener?.call();
    _alertSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_requestMobileNotificationPermissions());
      // v2.2.0: also trigger Layer A watcher on resume.
      _notificationService.checkDueNow();
    }
  }

  Future<void> _requestMobileNotificationPermissions() async {
    if (kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      return;
    }
    await _notificationService.requestPermissions();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _loadError = '';
    });
    try {
      final saved = await _store.read();
      final document = saved == null
          ? BackupDocument(tasks: _sampleTasks())
          : BackupDocument.fromJsonString(saved);
      if (saved == null) await _store.write(document.toPrettyJson());
      if (!mounted) return;
      if (kIsWeb) {
        _isIosSafari = isIosSafari;
        _storagePersisted = await persistStorage();
        if (!mounted) return;
      }
      setState(() {
        _tasks = document.tasks;
        _isFirstLaunch = saved == null;
        _themeMode = document.themeMode == 'dark'
            ? ThemeMode.dark
            : ThemeMode.light;
        _isLoading = false;
      });
      for (final task in document.tasks) {
        unawaited(_syncTaskReminder(task));
      }
      unawaited(_notificationService.syncTasks(document.tasks));
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Saved data is invalid: ${error.message}';
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load local data: $error';
      });
    }
  }

  List<TodoTask> _sampleTasks() => [
    TodoTask(
      id: 'sample-today-plan',
      title: 'Plan the week',
      notes: 'Take a few minutes to get organized.',
      priority: Priority.high,
      bucket: TaskBucket.today,
      tags: ['planning', 'personal'],
      subtasks: [
        Subtask(id: 'sample-plan-1', title: 'Review calendar'),
        Subtask(id: 'sample-plan-2', title: 'Pick top priorities'),
        Subtask(id: 'sample-plan-3', title: 'Make a shopping list'),
      ],
    ),
    TodoTask(
      id: 'sample-upcoming',
      title: 'Book a dentist appointment',
      notes: 'Call the clinic this week.',
      priority: Priority.medium,
      bucket: TaskBucket.upcoming,
      tags: ['health'],
    ),
    TodoTask(
      id: 'sample-completed',
      title: 'Water the houseplants',
      priority: Priority.low,
      bucket: TaskBucket.completed,
      kanbanColumn: KanbanColumn.done,
      tags: ['home'],
    ),
    TodoTask(
      id: 'sample-today',
      title: 'Take a walk outside',
      notes: 'A little fresh air goes a long way.',
      priority: Priority.low,
      bucket: TaskBucket.today,
      tags: ['wellbeing'],
    ),
  ];

  Future<void> _persist() async {
    unawaited(_notificationService.syncTasks(_tasks));
    final document = BackupDocument(
      tasks: List.unmodifiable(_tasks),
      themeMode: _themeMode == ThemeMode.dark ? 'dark' : 'light',
    );
    final snapshot = document.toPrettyJson();
    _pendingWrites++;
    setState(() => _isSaving = true);
    final write = _writeQueue
        .catchError((Object _) {})
        .then((_) => _store.write(snapshot));
    _writeQueue = write;
    try {
      await write;
    } on Exception catch (error) {
      _showMessage('Could not save your changes locally: $error');
    } finally {
      _pendingWrites--;
      if (mounted) setState(() => _isSaving = _pendingWrites > 0);
    }
  }

  void _showMessage(String message, {String? action, VoidCallback? onAction}) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action == null
              ? null
              : SnackBarAction(label: action, onPressed: onAction!),
        ),
      );
  }

  Future<void> _promptPwaInstall() async {
    if (!kIsWeb || isStandalonePwa) return;
    final result = await minidoPromptInstall();
    if (!mounted) return;
    if (result == 'accepted') {
      setState(() => _dismissedInstallBanner = true);
    } else if (result == 'unavailable') {
      await _showAddToHomeScreenGuide();
    } else {
      _showMessage('You can install Minido any time from your browser menu.');
    }
  }

  Future<void> _enableReminders() async {
    if (kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform)) {
      _showMessage(
        'Local reminders are available in the Android, iPhone, iPad, and Mac apps.',
      );
      return;
    }
    final granted = await _notificationService.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      _showMessage('Reminder permission was not granted.');
      return;
    }
    for (final task in _tasks) {
      await _syncTaskReminder(task);
    }
    _showMessage('Reminders are enabled for tasks with due dates.');
  }

  Future<void> _syncTaskReminder(TodoTask task) async {
    if (task.isCancelled || task.isCompleted || task.dueAt == null) {
      await _notificationService.scheduleTaskReminders(
        taskId: task.id,
        title: task.title,
        dueDate: task.dueAt,
        isCompleted: task.isCompleted,
        isCancelled: task.isCancelled,
        reminderOffsetMinutes: task.reminderOffsetMinutes,
      );
      return;
    }
    await _notificationService.scheduleTaskReminders(
      taskId: task.id,
      title: task.title,
      dueDate: task.dueAt!,
      isCompleted: task.isCompleted,
      isCancelled: task.isCancelled,
      reminderOffsetMinutes: task.reminderOffsetMinutes,
    );
  }

  Future<void> _showAddToHomeScreenGuide() async {
    final canInstallNow = kIsWeb && canPromptInstall;
    await showDialog<void>(
      context: _navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Install Minido / Add to Home Screen'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canInstallNow)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FilledButton.icon(
                      onPressed: () => unawaited(_promptPwaInstall()),
                      icon: const Icon(Icons.install_mobile),
                      label: const Text('Install Now (1-Tap)'),
                    ),
                  ),
                _installGuideSection(
                  context,
                  'Android',
                  'Chrome, Edge, Brave — Android 8+',
                  const [
                    'Open Minido in Chrome, Edge, or Brave.',
                    'Tap the three-dot menu (\u22ee) in the top-right corner.',
                    'Tap Add to home screen -> choose Install (or tap Install app directly).',
                    'Confirm Install — Minido appears in your app drawer as a full-screen app (or download the direct .apk from GitHub Releases if sideloading).',
                  ],
                ),
                _installGuideSection(
                  context,
                  'iPhone & iPad',
                  'Safari — iOS 16.4+ / iPadOS 16.4+ & iOS 18+',
                  const [
                    'Open Minido in Safari. Apple restricts Home Screen web apps primarily to Safari; on iOS 16.4+, third-party browsers must also use the Share sheet.',
                    'Tap the Share button (square with an upward arrow \u238b at the bottom bar on iPhone, or top-right on iPad).',
                    'Scroll down the action list and tap Add to Home Screen.',
                    'Verify the name is Minido and tap Add in the top-right corner.',
                  ],
                ),
                _installGuideSection(
                  context,
                  'Windows',
                  'Windows 10 & Windows 11 — Chrome, Edge, Brave',
                  const [
                    'Open Minido in Microsoft Edge or Google Chrome.',
                    'Click the Install icon (monitor with a down arrow or + inside a circle) on the right side of the address bar.',
                    'Or open the browser menu (\u22ef in Edge / \u22ee in Chrome) -> Apps -> Install this site as an app.',
                    'Click Install — you can pin Minido to your Windows Taskbar or Start Menu.',
                  ],
                ),
                _installGuideSection(
                  context,
                  'macOS',
                  'Sonoma 14+, Sequoia 15+, Tahoe 26+',
                  const [
                    'Safari (macOS 14 Sonoma or newer): Click File in the top macOS menu bar -> Add to Dock... -> click Add.',
                    'Chrome / Edge / Brave (macOS 11+): Click the Install icon in the right side of the address bar, or menu \u22ee -> Cast, save, and share -> Install page as app...',
                  ],
                ),
                _installGuideSection(
                  context,
                  'Linux',
                  'Ubuntu, Fedora, Arch, Mint — Chrome, Chromium, Brave, Edge',
                  const [
                    'Open Minido in Chrome, Chromium, Brave, or Edge. Standard desktop Firefox does not support standalone PWA installation natively without an extension.',
                    'Click the Install icon in the address bar, or open menu (\u22ee) -> Cast, save, and share -> Install Minido...',
                    'Click Install — Minido creates a .desktop launcher entry in your system application menu.',
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Local-First Storage Tip: Each browser and installed app keeps its own private storage. To move your tasks after installing, export a .json backup from the browser and Smart-Merge it into the installed app.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _installGuideSection(
    BuildContext context,
    String title,
    String subtitle,
    List<String> steps,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(child: Text(steps[i])),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showQuickAddConfirmation() async {
    final draft = _quickDraft;
    final dueAt = _dueAt ?? _liveParseResult?.dateTime;
    var reminderOffsetMinutes = _quickReminderOffsetMinutes;
    final result = await showDialog<bool>(
      context: _navigatorKey.currentContext!,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create task'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text('Title: ${draft.title}'),
                const SizedBox(height: 6),
                Text('Priority: ${_priorityName(draft.priority)}'),
                const SizedBox(height: 6),
                Text(
                  'Scheduled Date & Time: ${dueAt == null ? 'No due date' : _formatDateTime(dueAt)}',
                ),
                const SizedBox(height: 6),
                Text(
                  'Tags: ${draft.tags.isEmpty ? 'None' : draft.tags.join(', ')}',
                ),
                const SizedBox(height: 12),
                _ReminderOffsetSelector(
                  value: reminderOffsetMinutes,
                  onChanged: (value) =>
                      setDialogState(() => reminderOffsetMinutes = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm & Create'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final task = TodoTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: draft.title,
      priority: draft.priority,
      bucket: draft.bucket,
      tags: List.unmodifiable(draft.tags),
      dueAt: dueAt,
      reminderOffsetMinutes: reminderOffsetMinutes,
    );
    setState(() {
      _tasks = [..._tasks, task];
      _quickAddController.clear();
      _dueAt = null;
      _parsedDateCleared = false;
      _quickReminderOffsetMinutes = reminderOffsetMinutes;
    });
    unawaited(_syncTaskReminder(task));
    unawaited(_persist());
  }

  void _addQuickTask() {
    final draft = _quickDraft;
    if (draft.title.isEmpty) return;
    unawaited(_showQuickAddConfirmation());
  }

  void _replaceTask(TodoTask task) {
    final normalizedTask =
        (task.isCompleted || task.isCancelled) && task.isFocus
        ? task.copyWith(isFocus: false)
        : task;
    setState(() {
      _tasks = [
        for (final existing in _tasks)
          if (existing.id == normalizedTask.id) normalizedTask else existing,
      ];
    });
    unawaited(_syncTaskReminder(normalizedTask));
    unawaited(_persist());
  }

  void _toggleFocus(TodoTask task) {
    if (task.isCompleted || task.isCancelled) return;
    final adding = !task.isFocus;
    final focusedCount = _tasks
        .where(
          (item) =>
              item.isFocus &&
              !item.isCancelled &&
              item.bucket != TaskBucket.completed,
        )
        .length;
    if (adding && !MinidoFocus.canAdd(focusedCount)) {
      _showMessage(MinidoFocus.fullMsg);
      return;
    }
    _replaceTask(
      task.copyWith(isFocus: adding, updatedAt: DateTime.now().toUtc()),
    );
  }

  void _snoozeTask(TodoTask task) {
    final undo = MinidoUndo(
      label: task.title,
      snapshot: MinidoUndo.clone([task.toJson()]),
    );
    final snoozed = task.copyWith(
      dueAt: MinidoSnooze.tomorrow(task.dueAt),
      updatedAt: DateTime.now().toUtc(),
    );
    _replaceTask(snoozed);
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Snoozed "${undo.label}" until tomorrow'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => _undoSnooze(undo),
          ),
        ),
      );
  }

  void _undoSnooze(MinidoUndo undo) {
    if (undo.snapshot.isEmpty) return;
    final restored = TodoTask.fromJson(undo.snapshot.first);
    final index = _tasks.indexWhere((task) => task.id == restored.id);
    setState(() {
      final updated = List<TodoTask>.of(_tasks);
      if (index < 0) {
        updated.add(restored);
      } else {
        updated[index] = restored;
      }
      _tasks = updated;
    });
    unawaited(_syncTaskReminder(restored));
    unawaited(_persist());
  }

  void _toggleCompletion(TodoTask task) {
    final now = DateTime.now().toUtc();
    final updated = task.bucket == TaskBucket.completed
        ? task.copyWith(
            bucket: TaskBucket.upcoming,
            kanbanColumn: KanbanColumn.toDo,
            updatedAt: now,
            clearCompletedAt: true,
          )
        : task.copyWith(
            bucket: TaskBucket.completed,
            kanbanColumn: KanbanColumn.done,
            updatedAt: now,
            completedAt: now,
            isFocus: false,
          );
    _replaceTask(updated);
    _showMessage(
      task.bucket == TaskBucket.completed ? 'Task reopened' : 'Task completed',
      action: 'Undo',
      onAction: () => _replaceTask(task),
    );
  }

  void _cancelTask(TodoTask task, {String? cancelReason}) {
    final now = DateTime.now().toUtc();
    final cancelled = task.copyWith(
      isCancelled: true,
      cancelledAt: now,
      updatedAt: now,
      isFocus: false,
    );
    setState(() {
      _tasks = [
        for (final existing in _tasks)
          if (existing.id == task.id) cancelled else existing,
      ];
    });
    unawaited(_syncTaskReminder(cancelled));
    unawaited(_persist());
    // v2.2.0: show cancellation reason chips in the snackbar.
    _showCancelSnackBar(task, cancelReason: cancelReason);
  }

  void _showCancelSnackBar(TodoTask task, {String? cancelReason}) {
    final reasons = ['No longer needed', 'Delegated', 'Overcommitted'];
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Task cancelled${cancelReason != null ? ' · $cancelReason' : ''}'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in reasons)
                    ActionChip(
                      label: Text(r, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _messengerKey.currentState?.hideCurrentSnackBar();
                        _cancelTask(task, cancelReason: r);
                      },
                    ),
                ],
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _uncancelTask(task),
          ),
        ),
      );
  }

  void _uncancelTask(TodoTask task) {
    TodoTask? existing;
    for (final item in _tasks) {
      if (item.id == task.id) {
        existing = item;
        break;
      }
    }
    if (existing == null || !existing.isCancelled) return;
    final restored = existing.copyWith(
      isCancelled: false,
      clearCancelledAt: true,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() {
      _tasks = [
        for (final item in _tasks)
          if (item.id == task.id) restored else item,
      ];
    });
    unawaited(_syncTaskReminder(restored));
    unawaited(_persist());
  }

  void _moveTask(TodoTask task, KanbanColumn column) {
    final now = DateTime.now().toUtc();
    final updated = task.copyWith(
      kanbanColumn: column,
      isFocus: column == KanbanColumn.done ? false : task.isFocus,
      bucket: column == KanbanColumn.done
          ? TaskBucket.completed
          : task.bucket == TaskBucket.completed
          ? TaskBucket.upcoming
          : task.bucket,
      updatedAt: now,
      completedAt: column == KanbanColumn.done ? now : null,
      clearCompletedAt: column != KanbanColumn.done,
    );
    _replaceTask(updated);
  }

  Future<void> _editTask(TodoTask task) async {
    final result = await showDialog<_EditorResult>(
      context: _navigatorKey.currentContext!,
      builder: (context) => _TaskEditor(task: task),
    );
    if (!mounted || result == null) return;
    if (result.cancelled) {
      _cancelTask(task, cancelReason: null);
    } else if (result.task != null) {
      _replaceTask(result.task!);
    }
  }

  Future<void> _clearSampleTasks() async {
    setState(() => _tasks = _tasks.where((task) => !task.isSample).toList());
    await _persist();
  }

  String _formatDateTime(DateTime time) {
    final local = time.toLocal();
    return '${_monthNames[local.month - 1]} ${local.day}, ${local.year} at ${_formatClock(local)}';
  }

  void _loadSampleTasks() {
    final added = <TodoTask>[
      TodoTask(
        id: 'sample-load-plan',
        title: 'Plan the week',
        notes: 'Review goals and set top priorities.',
        priority: Priority.high,
        bucket: TaskBucket.today,
        tags: ['planning', 'personal'],
        subtasks: [
          Subtask(id: 'load-plan-1', title: 'Review calendar'),
          Subtask(id: 'load-plan-2', title: 'Pick top priorities'),
          Subtask(id: 'load-plan-3', title: 'Make a shopping list'),
        ],
      ),
      TodoTask(
        id: 'sample-load-dentist',
        title: 'Book a dentist appointment',
        notes: 'Call the clinic this week.',
        priority: Priority.medium,
        bucket: TaskBucket.upcoming,
        tags: ['health'],
      ),
      TodoTask(
        id: 'sample-load-grocery',
        title: 'Grocery shopping',
        notes: 'Milk, eggs, bread, and fruit.',
        priority: Priority.low,
        bucket: TaskBucket.upcoming,
        tags: ['home', 'errands'],
      ),
      TodoTask(
        id: 'sample-load-plants',
        title: 'Water the houseplants',
        priority: Priority.low,
        bucket: TaskBucket.completed,
        kanbanColumn: KanbanColumn.done,
        tags: ['home'],
      ),
    ];
    setState(() => _tasks = [..._tasks, ...added]);
    unawaited(_persist());
    _showMessage('Sample tasks loaded');
  }

  String _backupFileName() {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'minido-backup-$date.json';
  }

  Future<void> _showExportDialog() async {
    final exportJson = const JsonEncoder.withIndent('  ')
        .convert(<String, Object?>{
          'version': 1,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'tasks': _tasks.map((task) => task.toJson()).toList(),
        });
    final lastExported = _lastExported;
    await showDialog<void>(
      context: _navigatorKey.currentContext!,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export backup'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Last exported: ${lastExported == null ? 'Not exported yet' : _formatDateTime(lastExported)}',
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Exports every task as formatted JSON.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: exportJson));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _showMessage('Backup copied to clipboard');
              } on Exception catch (error) {
                _showMessage('Could not copy backup: $error');
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy JSON'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                final bytes = utf8.encode(exportJson);
                final fileName = _backupFileName();
                final saved = await FilePicker.saveFile(
                  dialogTitle: 'Save Minido Backup',
                  fileName: fileName,
                  bytes: bytes,
                );
                if (!dialogContext.mounted) return;
                if (saved == null) {
                  _showMessage('Backup was not saved');
                  return;
                }
                _lastExported = DateTime.now().toUtc();
                Navigator.pop(dialogContext);
                _showMessage('Backup exported');
              } on Exception catch (error) {
                _showMessage('Could not export backup: $error');
              }
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save .json File'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final result = await showDialog<_ImportResult>(
      context: _navigatorKey.currentContext!,
      builder: (context) => const _ImportDialog(),
    );
    if (!mounted || result == null) return;
    List<TodoTask> imported;
    try {
      imported = _parseImportedTasks(result.source);
    } on FormatException catch (error) {
      _showMessage('Invalid backup: ${error.message}');
      return;
    } on Exception catch (error) {
      _showMessage('Could not parse backup: $error');
      return;
    }
    final replaceAll = result.replaceAll;
    final previousTasks = _tasks;
    int added = 0;
    int updated = 0;
    if (replaceAll) {
      setState(() => _tasks = List.unmodifiable(imported));
    } else {
      final byId = <String, TodoTask>{for (final t in _tasks) t.id: t};
      final merged = <TodoTask>[];
      final importedIds = <String>{};
      for (final imp in imported) {
        importedIds.add(imp.id);
        final existing = byId[imp.id];
        if (existing == null) {
          merged.add(imp);
          added++;
        } else {
          final importedWins =
              imp.updatedAt.isAfter(existing.updatedAt) ||
              imp.updatedAt == existing.updatedAt;
          merged.add(importedWins ? imp : existing);
          if (importedWins) updated++;
        }
      }
      for (final t in _tasks) {
        if (!importedIds.contains(t.id)) merged.add(t);
      }
      setState(() => _tasks = List.unmodifiable(merged));
    }
    final retainedIds = _tasks.map((task) => task.id).toSet();
    for (final task in previousTasks) {
      if (!retainedIds.contains(task.id)) {
        unawaited(_notificationService.cancelTaskReminders(task.id));
      }
    }
    for (final task in _tasks) {
      unawaited(_syncTaskReminder(task));
    }
    await _persist();
    if (!mounted) return;
    _showMessage(
      replaceAll
          ? 'Imported: ${imported.length} replaced'
          : 'Imported: $added added, $updated updated',
    );
  }

  List<TodoTask> get _visibleTasks {
    final query = _search.trim().toLowerCase();
    return _tasks.where((task) {
      final matchesSearch =
          query.isEmpty ||
          task.title.toLowerCase().contains(query) ||
          task.notes.toLowerCase().contains(query) ||
          task.tags.any((tag) => tag.toLowerCase().contains(query));
      final matchesPriority =
          _priorityFilter == null || task.priority == _priorityFilter;
      final matchesTags =
          _tagFilters.isEmpty || _tagFilters.every(task.tags.contains);
      final matchesStatus = _viewMode == 'cancelled'
          ? task.isCancelled
          : !task.isCancelled;
      return matchesSearch && matchesPriority && matchesTags && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Minido',
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: _messengerKey,
    navigatorKey: _navigatorKey,
    themeMode: _themeMode,
    theme: ThemeData(
      useMaterial3: true,
      // v2.2.0: Warm Paper — #FAF8F5 surface, #18181B ink, #C2410C accent.
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFC2410C),
        surface: const Color(0xFFFAF8F5),
      ).copyWith(
        onSurface: const Color(0xFF18181B),
        primary: const Color(0xFFC2410C),
        onPrimary: const Color(0xFFFAF8F5),
      ),
      scaffoldBackgroundColor: const Color(0xFFFAF8F5),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      // v2.2.0: OLED Pitch Black — #000000 surface, #F4F4F5 ink, #FB923C accent.
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFB923C),
        brightness: Brightness.dark,
        surface: const Color(0xFF000000),
      ).copyWith(
        onSurface: const Color(0xFFF4F4F5),
        primary: const Color(0xFFFB923C),
        onPrimary: const Color(0xFF000000),
      ),
      scaffoldBackgroundColor: const Color(0xFF000000),
    ),
    home: Builder(
      builder: (context) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final focusContext = FocusManager.instance.primaryFocus?.context;
          final isEditing =
              focusContext?.widget is EditableText ||
              focusContext?.findAncestorWidgetOfExactType<EditableText>() !=
                  null;
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.slash &&
              !isEditing) {
            _quickAddFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _buildHome(context),
      ),
    ),
  );

  Widget _buildHome(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MinidoResponsive.isCompact(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/brand/minido_logo.png'),
              width: 28,
              height: 28,
            ),
            SizedBox(width: 10),
            Text('Minido'),
          ],
        ),
        actions: [
          if (compact) _compactViewToggle(),
          if (!compact && _isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (kIsWeb) _offlineReadyPill(),
          if (!compact)
            IconButton(
              tooltip: _craftTheme == 'oled'
                  ? 'Switch to Warm Paper theme'
                  : 'Switch to OLED Pitch Black theme',
              constraints: const BoxConstraints(
                minWidth: MinidoResponsive.tapTarget,
                minHeight: MinidoResponsive.tapTarget,
              ),
              onPressed: _toggleTheme,
              icon: Icon(
                _craftTheme == 'oled'
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Backup and restore',
            icon: const Icon(Icons.more_vert),
            onSelected: (choice) {
              switch (choice) {
                case 'install-help':
                  unawaited(_showAddToHomeScreenGuide());
                case 'export':
                  unawaited(_showExportDialog());
                case 'import':
                  unawaited(_showImportDialog());
                case 'cancelled':
                  setState(() => _viewMode = 'cancelled');
                case 'list':
                  setState(() => _viewMode = 'list');
                case 'kanban':
                  setState(() => _viewMode = 'kanban');
                case 'statistics':
                  setState(() => _viewMode = 'statistics');
                case 'reminders':
                  unawaited(_enableReminders());
                case 'test-reminder':
                  unawaited(
                    _notificationService.triggerTestReminder().then(
                      (status) => _showMessage(status),
                    ),
                  );
                case 'theme':
                  _toggleTheme();
                case 'load-samples':
                  _loadSampleTasks();
              }
            },
            itemBuilder: (context) => [
              if (kIsWeb && isStandalonePwa)
                const PopupMenuItem(
                  value: 'install-help',
                  child: ListTile(
                    leading: Icon(Icons.install_desktop),
                    title: Text('Install on Other Devices'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (kIsWeb && !isStandalonePwa)
                const PopupMenuItem(
                  value: 'install-help',
                  child: ListTile(
                    leading: Icon(Icons.install_mobile),
                    title: Text('Add to Home Screen'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'reminders',
                child: ListTile(
                  leading: Icon(Icons.notifications_active_outlined),
                  title: Text('Enable reminders'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'test-reminder',
                child: ListTile(
                  leading: Icon(Icons.notifications_active),
                  title: Text('Test Reminder (5s)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (compact)
                PopupMenuItem(
                  value: 'theme',
                  child: ListTile(
                    leading: Icon(
                      _themeMode == ThemeMode.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                    title: Text(
                      _themeMode == ThemeMode.dark
                          ? 'Light theme'
                          : 'Dark theme',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('Export JSON'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('Import JSON'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!compact) const PopupMenuDivider(),
              if (!compact)
                const PopupMenuItem(
                  value: 'list',
                  child: ListTile(
                    leading: Icon(Icons.view_list),
                    title: Text('List'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!compact)
                const PopupMenuItem(
                  value: 'kanban',
                  child: ListTile(
                    leading: Icon(Icons.view_kanban_outlined),
                    title: Text('Kanban'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'cancelled',
                child: ListTile(
                  leading: Icon(Icons.cancel_outlined),
                  title: Text('Cancelled'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'statistics',
                child: ListTile(
                  leading: Icon(Icons.bar_chart_outlined),
                  title: Text('Statistics'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'load-samples',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Load Sample Tasks'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError.isNotEmpty
          ? _LoadError(message: _loadError, onRetry: _initialize)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isFirstLaunch && !_dismissedWelcomeCard)
                  _firstRunWelcomeCard(),
                if (kIsWeb && !isStandalonePwa && !_dismissedInstallBanner)
                  _installBanner(),
                // v2.2.0: Due reminder banner from Layer A alerts.
                if (_activeAlert != null) _buildAlertBanner(_activeAlert!),
                // v2.2.0: Morning rollover banner.
                if (!_dismissedRollover && _rolloverTasks.isNotEmpty)
                  _buildRolloverBanner(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: _buildWorkspace(theme),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _compactViewToggle() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(MinidoResponsive.tapTarget, MinidoResponsive.tapTarget),
        ),
        visualDensity: VisualDensity.compact,
      ),
      segments: const [
        ButtonSegment(
          value: 'list',
          icon: Icon(Icons.view_list),
          tooltip: 'List view',
        ),
        ButtonSegment(
          value: 'kanban',
          icon: Icon(Icons.view_kanban_outlined),
          tooltip: 'Kanban view',
        ),
      ],
      selected: {_viewMode == 'kanban' ? 'kanban' : 'list'},
      onSelectionChanged: (selection) =>
          setState(() => _viewMode = selection.first),
    ),
  );

  void _toggleTheme() {
    // v2.2.0: cycle through craft themes: warm → oled → warm
    setState(() {
      if (_craftTheme == 'warm') {
        _craftTheme = 'oled';
        _themeMode = ThemeMode.dark;
      } else {
        _craftTheme = 'warm';
        _themeMode = ThemeMode.light;
      }
    });
    unawaited(_persist());
  }

  Widget _offlineReadyPill() {
    if (!_storagePersisted) return const SizedBox.shrink();
    final compact = MinidoResponsive.isCompact(context);
    return Tooltip(
      message: 'Offline Ready — your tasks are saved on this device',
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 6),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 9,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Offline Ready',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // v2.2.0: Due-reminder alert banner (Layer A driven).
  Widget _buildAlertBanner(AlertEvent event) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.alarm, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '⏰ Due: ${event.title}',
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final idx = _tasks.indexWhere((t) => t.id == event.taskId);
              if (idx >= 0) _toggleCompletion(_tasks[idx]);
              setState(() => _activeAlert = null);
            },
            child: const Text('Done'),
          ),
          TextButton(
            onPressed: () {
              final idx = _tasks.indexWhere((t) => t.id == event.taskId);
              if (idx >= 0) _snoozeTask(_tasks[idx]);
              setState(() => _activeAlert = null);
            },
            child: const Text('+1d'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _activeAlert = null),
          ),
        ],
      ),
    );
  }

  // v2.2.0: Morning rollover banner.
  Widget _buildRolloverBanner() {
    final theme = Theme.of(context);
    final tasks = _rolloverTasks;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_sunny_outlined,
              color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${tasks.length} task${tasks.length == 1 ? '' : 's'} from earlier — roll over?',
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final now = DateTime.now().toUtc();
              final todayEnd = DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
                23,
                59,
              ).toUtc();
              setState(() {
                _tasks = [
                  for (final t in _tasks)
                    if (tasks.any((r) => r.id == t.id))
                      t.copyWith(
                        bucket: TaskBucket.today,
                        dueAt: t.dueAt ?? todayEnd,
                        updatedAt: now,
                      )
                    else
                      t,
                ];
                _dismissedRollover = true;
              });
              unawaited(_persist());
            },
            child: const Text('Move to Today'),
          ),
          TextButton(
            onPressed: () {
              for (final t in tasks) {
                _snoozeTask(t);
              }
              setState(() => _dismissedRollover = true);
            },
            child: const Text('Snooze +1d'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Dismiss',
            onPressed: () => setState(() => _dismissedRollover = true),
          ),
        ],
      ),
    );
  }

  Widget _firstRunWelcomeCard() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.waving_hand_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Welcome to Minido! Add a task above, or try !high, #work, today, or tomorrow. Your tasks stay private on this device.',
            ),
          ),
          IconButton(
            tooltip: 'Dismiss welcome message',
            onPressed: () => setState(() => _dismissedWelcomeCard = true),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _installBanner() {
    final theme = Theme.of(context);
    final canInstallNow = canPromptInstall;
    final subtitle = _isIosSafari
        ? 'Tap Share ⎋ → Add to Home Screen'
        : canInstallNow
        ? 'Use Minido in its own app window, without browser tabs.'
        : 'Add Minido from your browser menu for an app-like experience.';

    Widget installAction() {
      if (_isIosSafari) {
        return OutlinedButton(
          onPressed: () => unawaited(_showAddToHomeScreenGuide()),
          child: const Text('How?'),
        );
      }
      if (canInstallNow) {
        return FilledButton.icon(
          onPressed: () => unawaited(_promptPwaInstall()),
          icon: const Icon(Icons.install_mobile, size: 18),
          label: const Text('Add to Home Screen'),
        );
      }
      return OutlinedButton(
        onPressed: () => unawaited(_promptPwaInstall()),
        child: const Text('Add to Home Screen'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final message = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isIosSafari
                    ? 'Add Minido to your Home Screen'
                    : 'Install Minido on this device',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        );
        final dismissButton = IconButton(
          tooltip: 'Dismiss install help',
          onPressed: () => setState(() => _dismissedInstallBanner = true),
          icon: const Icon(Icons.close),
        );

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.install_mobile, size: 20),
                        const SizedBox(width: 10),
                        message,
                        dismissButton,
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: installAction(),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Icon(Icons.install_mobile, size: 20),
                    const SizedBox(width: 10),
                    message,
                    const SizedBox(width: 12),
                    installAction(),
                    dismissButton,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildWorkspace(ThemeData theme) {
    final compact = MinidoResponsive.isCompact(context);
    if (_viewMode == 'statistics') {
      return Padding(
        padding: EdgeInsets.all(MinidoResponsive.pad(context)),
        child: _StatisticsView(
          tasks: _tasks,
          periodDays: _statisticsPeriodDays,
          onPeriodChanged: (days) =>
              setState(() => _statisticsPeriodDays = days),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MinidoResponsive.pad(context),
        8,
        MinidoResponsive.pad(context),
        compact ? 8 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact) _buildQuickAddCard(theme, compact: false),
          if (!compact) const SizedBox(height: 12),
          _buildFilters(theme, compact: compact),
          const SizedBox(height: 8),
          Expanded(
            child: _viewMode == 'cancelled'
                ? _buildCancelledTasks(_visibleTasks)
                : _viewMode == 'kanban'
                ? _KanbanBoard(
                    tasks: _visibleTasks,
                    onOpen: _editTask,
                    onMove: _moveTask,
                    onToggleFocus: _toggleFocus,
                    onSnooze: _snoozeTask,
                  )
                : _TaskList(
                    tasks: _visibleTasks,
                    onOpen: _editTask,
                    onToggleCompletion: _toggleCompletion,
                    onToggleFocus: _toggleFocus,
                    onSnooze: _snoozeTask,
                  ),
          ),
          if (compact && _viewMode != 'cancelled') ...[
            const SizedBox(height: 8),
            _buildQuickAddCard(theme, compact: true),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickAddCard(ThemeData theme, {required bool compact}) {
    final draft = _quickDraft;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 16,
          vertical: compact ? 4 : 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (!compact) ...[
                  const Icon(Icons.add_task),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: TextField(
                    controller: _quickAddController,
                    focusNode: _quickAddFocus,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: compact
                          ? 'Add a task...'
                          : 'Add a task... try "Call Sam !high #work today"',
                      border: InputBorder.none,
                      isDense: compact,
                    ),
                    onChanged: (_) => setState(() {
                      _parsedDateCleared = false;
                    }),
                    onSubmitted: (_) => _addQuickTask(),
                  ),
                ),
                const SizedBox(width: 4),
                if (compact)
                  IconButton.filled(
                    tooltip: 'Add task',
                    constraints: const BoxConstraints(
                      minWidth: MinidoResponsive.tapTarget,
                      minHeight: MinidoResponsive.tapTarget,
                    ),
                    onPressed: draft.title.isEmpty ? null : _addQuickTask,
                    icon: const Icon(Icons.add),
                  )
                else
                  FilledButton.icon(
                    onPressed: draft.title.isEmpty ? null : _addQuickTask,
                    icon: const Icon(Icons.add),
                    label: const Text('Add task'),
                  ),
              ],
            ),
            _DueDateControls(
              dueAt: _dueAt,
              onChanged: (value) => setState(() => _dueAt = value),
            ),
            // v2.2.0: Quick-parse live date preview pill.
            if (_liveParseResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event,
                            size: 14,
                            color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 4),
                        Text(
                          _liveParseResult!.matchedPhrase ?? '',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() {
                            _parsedDateCleared = true;
                          }),
                          child: Icon(Icons.close,
                              size: 14,
                              color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!compact)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Preview',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    _PriorityPill(priority: draft.priority),
                    _BucketPill(bucket: draft.bucket),
                    ...draft.tags.map((tag) => _TagPill(tag: tag)),
                    if (_quickAddController.text.trim().isEmpty)
                      Text(
                        'Use !high, !med, !low, #tags, today or tomorrow',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelledTasks(List<TodoTask> tasks) {
    if (tasks.isEmpty) {
      return const Center(child: Text('No cancelled tasks'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final task in tasks)
          _CancelledTaskCard(task: task, onRestore: () => _uncancelTask(task)),
      ],
    );
  }

  Widget _buildFilters(ThemeData theme, {required bool compact}) {
    final tags = _tasks.expand((task) => task.tags).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!compact)
              SegmentedButton<String>(
                style: _viewMode == 'cancelled'
                    ? ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? const Color(0xFFF4D5DC)
                              : null,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? const Color(0xFF762D42)
                              : null,
                        ),
                      )
                    : null,
                segments: const [
                  ButtonSegment(
                    value: 'list',
                    icon: Icon(Icons.view_list),
                    label: Text('List'),
                  ),
                  ButtonSegment(
                    value: 'kanban',
                    icon: Icon(Icons.view_kanban_outlined),
                    label: Text('Kanban'),
                  ),
                  ButtonSegment(
                    value: 'cancelled',
                    icon: Icon(Icons.cancel_outlined),
                    label: Text('Cancelled'),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selection) =>
                    setState(() => _viewMode = selection.first),
              ),
            SizedBox(
              width: 240,
              child: SearchBar(
                leading: const Icon(Icons.search),
                hintText: 'Search tasks',
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            DropdownButton<Priority?>(
              value: _priorityFilter,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(14),
              items: const [
                DropdownMenuItem<Priority?>(child: Text('Any priority')),
                DropdownMenuItem(
                  value: Priority.high,
                  child: Text('High priority'),
                ),
                DropdownMenuItem(
                  value: Priority.medium,
                  child: Text('Medium priority'),
                ),
                DropdownMenuItem(
                  value: Priority.low,
                  child: Text('Low priority'),
                ),
              ],
              onChanged: (value) => setState(() => _priorityFilter = value),
            ),
            if (_tasks.any((task) => task.isSample))
              TextButton.icon(
                onPressed: _clearSampleTasks,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Clear sample data'),
              ),
          ],
        ),
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text('Tags', style: theme.textTheme.labelMedium),
                  const SizedBox(width: 6),
                  ...tags.map(
                    (tag) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('#$tag'),
                        selected: _tagFilters.contains(tag),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _tagFilters.add(tag);
                          } else {
                            _tagFilters.remove(tag);
                          }
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

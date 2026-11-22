import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'models/task_models.dart';
import 'data/task_store.dart';
import 'services/pwa_install.dart';

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

class _MinidoAppState extends State<MinidoApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _quickAddFocus = FocusNode();
  final _quickAddController = TextEditingController();
  late final TaskStore _store = widget.store ?? SharedPreferencesTaskStore();

  List<TodoTask> _tasks = const [];
  ThemeMode _themeMode = ThemeMode.light;
  Priority? _priorityFilter;
  final Set<String> _tagFilters = {};
  String _search = '';
  String _loadError = '';
  bool _isLoading = true;
  bool _isSaving = false;
  int _pendingWrites = 0;
  Future<void> _writeQueue = Future<void>.value();
  String _viewMode = 'list'; // 'list' | 'kanban' | 'cancelled' | 'statistics'
  int _statisticsPeriodDays = 7;
  DateTime? _dueAt;
  DateTime? _lastExported;

  QuickAddDraft get _quickDraft => parseQuickAdd(_quickAddController.text);

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _quickAddFocus.dispose();
    _quickAddController.dispose();
    super.dispose();
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
      setState(() {
        _tasks = document.tasks;
        _themeMode = document.themeMode == 'dark'
            ? ThemeMode.dark
            : ThemeMode.light;
        _isLoading = false;
      });
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

  void _installApp() {
    if (!kIsWeb) return;
    if (canPromptInstall) {
      triggerInstallPrompt();
      return;
    }
    unawaited(_showAddToHomeScreenGuide());
  }

  Future<void> _showAddToHomeScreenGuide() async {
    await showDialog<void>(
      context: _navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Add Minido to Home Screen'),
        content: const Text(
          'iOS Safari: Tap Share, then Add to Home Screen.\n\n'
          'Android Chrome: Open menu ⋮, then choose Install app or Add to home screen.\n\n'
          'Desktop browsers: Select the install icon in the address bar.\n\n'
          'Use JSON Export and Smart Merge to transfer tasks between the browser and installed app.',
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

  Future<void> _showQuickAddConfirmation() async {
    final draft = _quickDraft;
    final dueAt = _dueAt;
    final task = TodoTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: draft.title,
      priority: draft.priority,
      bucket: draft.bucket,
      tags: List.unmodifiable(draft.tags),
      dueAt: dueAt,
    );
    final result = await showDialog<bool>(
      context: _navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
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
    );
    if (result != true || !mounted) return;
    setState(() {
      _tasks = [..._tasks, task];
      _quickAddController.clear();
      _dueAt = null;
    });
    unawaited(_persist());
  }

  void _addQuickTask() {
    final draft = _quickDraft;
    if (draft.title.isEmpty) return;
    unawaited(_showQuickAddConfirmation());
  }

  void _replaceTask(TodoTask task) {
    setState(() {
      _tasks = [
        for (final existing in _tasks)
          if (existing.id == task.id) task else existing,
      ];
    });
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
          );
    _replaceTask(updated);
    _showMessage(
      task.bucket == TaskBucket.completed ? 'Task reopened' : 'Task completed',
      action: 'Undo',
      onAction: () => _replaceTask(task),
    );
  }

  void _cancelTask(TodoTask task) {
    final now = DateTime.now().toUtc();
    setState(() {
      _tasks = [
        for (final existing in _tasks)
          if (existing.id == task.id)
            existing.copyWith(
              isCancelled: true,
              cancelledAt: now,
              updatedAt: now,
            )
          else
            existing,
      ];
    });
    unawaited(_persist());
    _showMessage(
      'Task cancelled',
      action: 'Undo',
      onAction: () => _uncancelTask(task),
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
    setState(() {
      _tasks = [
        for (final item in _tasks)
          if (item.id == task.id)
            item.copyWith(
              isCancelled: false,
              clearCancelledAt: true,
              updatedAt: DateTime.now().toUtc(),
            )
          else
            item,
      ];
    });
    unawaited(_persist());
  }

  void _moveTask(TodoTask task, KanbanColumn column) {
    final now = DateTime.now().toUtc();
    final updated = task.copyWith(
      kanbanColumn: column,
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
      _cancelTask(task);
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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5266D7)),
      scaffoldBackgroundColor: const Color(0xFFF7F8FC),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9AA8FF),
        brightness: Brightness.dark,
      ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF5266D7)),
            SizedBox(width: 10),
            Text('Minido'),
          ],
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: _themeMode == ThemeMode.dark
                ? 'Switch to light theme'
                : 'Switch to dark theme',
            onPressed: () {
              setState(
                () => _themeMode = _themeMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              );
              unawaited(_persist());
            },
            icon: Icon(
              _themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Backup and restore',
            icon: const Icon(Icons.more_vert),
            onSelected: (choice) {
              switch (choice) {
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
                case 'load-samples':
                  _loadSampleTasks();
                case 'install':
                  _installApp();
              }
            },
            itemBuilder: (context) => [
              if (kIsWeb && !isStandalonePwa)
                const PopupMenuItem(
                  value: 'install',
                  child: ListTile(
                    leading: Icon(Icons.install_mobile),
                    title: Text('Install App'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ...const [
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
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'list',
                  child: ListTile(
                    leading: Icon(Icons.view_list),
                    title: Text('List'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
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
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError.isNotEmpty
          ? _LoadError(message: _loadError, onRetry: _initialize)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: _buildWorkspace(theme),
              ),
            ),
    );
  }

  Widget _buildWorkspace(ThemeData theme) {
    if (_viewMode == 'statistics') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: _StatisticsView(
          tasks: _tasks,
          periodDays: _statisticsPeriodDays,
          onPeriodChanged: (days) =>
              setState(() => _statisticsPeriodDays = days),
        ),
      );
    }
    final draft = _quickDraft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.add_task),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _quickAddController,
                          focusNode: _quickAddFocus,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: 'Add a task... try "Call Sam !high #work today"',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _addQuickTask(),
                        ),
                      ),
                      const SizedBox(width: 8),
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
          ),
          const SizedBox(height: 12),
          _buildFilters(theme),
          const SizedBox(height: 12),
          Expanded(
            child: _viewMode == 'cancelled'
                ? _buildCancelledTasks(_visibleTasks)
                : _viewMode == 'kanban'
                ? _KanbanBoard(
                    tasks: _visibleTasks,
                    onOpen: _editTask,
                    onMove: _moveTask,
                  )
                : _TaskList(
                    tasks: _visibleTasks,
                    onOpen: _editTask,
                    onToggleCompletion: _toggleCompletion,
                  ),
          ),
        ],
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

  Widget _buildFilters(ThemeData theme) {
    final tags = _tasks.expand((task) => task.tags).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
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

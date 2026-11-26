part of '../../main.dart';

class _EditorResult {
  const _EditorResult.saved(this.task) : cancelled = false;
  const _EditorResult.cancelled() : task = null, cancelled = true;

  final TodoTask? task;
  final bool cancelled;
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({required this.task});

  final TodoTask task;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(text: widget.task.title);
  late final _notesController = TextEditingController(text: widget.task.notes);
  late final _tagsController = TextEditingController(
    text: widget.task.tags.map((tag) => '#$tag').join(' '),
  );
  final _subtaskController = TextEditingController();
  late Priority _priority = widget.task.priority;
  late TaskBucket _bucket = widget.task.bucket;
  late KanbanColumn _column = widget.task.kanbanColumn;
  late List<Subtask> _subtasks = [...widget.task.subtasks];
  late DateTime? _dueAt = widget.task.dueAt;
  late int _reminderOffsetMinutes = widget.task.reminderOffsetMinutes;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  void _addSubtask() {
    final title = _subtaskController.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _subtasks.add(
        Subtask(
          id: '${widget.task.id}-sub-${DateTime.now().microsecondsSinceEpoch}',
          title: title,
        ),
      );
      _subtaskController.clear();
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final tags = _tagsController.text
        .split(RegExp(r'[\s,]+'))
        .map((tag) => tag.replaceFirst(RegExp(r'^#'), '').toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    final now = DateTime.now().toUtc();
    Navigator.pop(
      context,
      _EditorResult.saved(
        widget.task.copyWith(
          title: _titleController.text.trim(),
          notes: _notesController.text.trim(),
          priority: _priority,
          bucket: _bucket,
          kanbanColumn: _column,
          tags: tags,
          subtasks: List.unmodifiable(_subtasks),
          dueAt: _dueAt,
          clearDueAt: _dueAt == null,
          reminderOffsetMinutes: _reminderOffsetMinutes,
          isFocus: _bucket == TaskBucket.completed
              ? false
              : widget.task.isFocus,
          completedAt: _bucket == TaskBucket.completed
              ? widget.task.completedAt ?? now
              : null,
          clearCompletedAt: _bucket != TaskBucket.completed,
          updatedAt: now,
        ),
      ),
    );
  }

  Future<void> _cancelTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this task?'),
        content: const Text(
          'The task will be kept in your list and can be restored later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Task'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Task'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, const _EditorResult.cancelled());
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Task details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Add a task title'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Tags',
                        hintText: '#work #home',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DueDateControls(
                      dueAt: _dueAt,
                      onChanged: (value) => setState(() => _dueAt = value),
                    ),
                    const SizedBox(height: 12),
                    _ReminderOffsetSelector(
                      value: _reminderOffsetMinutes,
                      onChanged: (value) =>
                          setState(() => _reminderOffsetMinutes = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Priority>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                      ),
                      items: Priority.values
                          .map(
                            (priority) => DropdownMenuItem(
                              value: priority,
                              child: Text(_priorityName(priority)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _priority = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<TaskBucket>(
                      initialValue: _bucket,
                      decoration: const InputDecoration(
                        labelText: 'List section',
                        border: OutlineInputBorder(),
                      ),
                      items: TaskBucket.values
                          .map(
                            (bucket) => DropdownMenuItem(
                              value: bucket,
                              child: Text(_bucketName(bucket)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _bucket = value;
                            if (value == TaskBucket.completed) {
                              _column = KanbanColumn.done;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<KanbanColumn>(
                      initialValue: _column,
                      decoration: const InputDecoration(
                        labelText: 'Kanban column',
                        border: OutlineInputBorder(),
                      ),
                      items: KanbanColumn.values
                          .map(
                            (column) => DropdownMenuItem(
                              value: column,
                              child: Text(_columnName(column)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _column = value;
                            if (value == KanbanColumn.done) {
                              _bucket = TaskBucket.completed;
                            } else if (_bucket == TaskBucket.completed) {
                              _bucket = TaskBucket.upcoming;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Subtasks',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final subtask in _subtasks)
                      Row(
                        children: [
                          Checkbox(
                            value: subtask.isDone,
                            onChanged: (value) => setState(() {
                              _subtasks = [
                                for (final item in _subtasks)
                                  if (item.id == subtask.id)
                                    item.copyWith(isDone: value ?? false)
                                  else
                                    item,
                              ];
                            }),
                          ),
                          Expanded(
                            child: Text(
                              subtask.title,
                              style: subtask.isDone
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : null,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove subtask',
                            onPressed: () => setState(
                              () => _subtasks.removeWhere(
                                (item) => item.id == subtask.id,
                              ),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _subtaskController,
                            decoration: const InputDecoration(
                              hintText: 'Add a subtask',
                            ),
                            onSubmitted: (_) => _addSubtask(),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Add subtask',
                          onPressed: _addSubtask,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _cancelTask,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel Task'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReminderOffsetSelector extends StatelessWidget {
  const _ReminderOffsetSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const shortLabels = <int, String>{
      -1: 'Off',
      0: 'At due',
      15: '15m',
      60: '1h',
      1440: '1d',
    };
    final selected = MinidoReminder.offsetOptions.contains(value) ? value : 15;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reminder', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(44, 44)),
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              for (final offset in MinidoReminder.offsetOptions)
                ButtonSegment<int>(
                  value: offset,
                  label: Text(shortLabels[offset]!),
                  tooltip: MinidoReminder.labelFor(offset),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Scheduled local reminders run on native builds.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

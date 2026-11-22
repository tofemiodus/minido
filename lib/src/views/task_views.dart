part of '../../main.dart';

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    required this.onOpen,
    required this.onToggleCompletion,
  });

  final List<TodoTask> tasks;
  final ValueChanged<TodoTask> onOpen;
  final ValueChanged<TodoTask> onToggleCompletion;

  @override
  Widget build(BuildContext context) {
    final groups = [
      (TaskBucket.today, 'Today', Icons.today_outlined),
      (TaskBucket.upcoming, 'Upcoming', Icons.calendar_month_outlined),
      (TaskBucket.completed, 'Completed', Icons.check_circle_outline),
    ];
    final wide = MediaQuery.of(context).size.width >= 900;
    final sections = <Widget>[
      for (final (bucket, title, icon) in groups)
        _BucketSection(
          bucket: bucket,
          title: title,
          icon: icon,
          tasks: tasks.where((task) => task.bucket == bucket).toList(),
          onOpen: onOpen,
          onToggle: onToggleCompletion,
        ),
    ];
    if (wide) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in sections) Expanded(child: section),
            ],
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: sections,
    );
  }
}

class _BucketSection extends StatelessWidget {
  const _BucketSection({
    required this.bucket,
    required this.title,
    required this.icon,
    required this.tasks,
    required this.onOpen,
    required this.onToggle,
  });

  final TaskBucket bucket;
  final String title;
  final IconData icon;
  final List<TodoTask> tasks;
  final ValueChanged<TodoTask> onOpen;
  final ValueChanged<TodoTask> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Text(
                '${tasks.length}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        ...tasks.map(
          (task) => _TaskCard(
            task: task,
            onTap: () => onOpen(task),
            onToggle: () => onToggle(task),
          ),
        ),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Text(
              'No tasks here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onTap,
    required this.onToggle,
  });

  final TodoTask task;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = task.bucket == TaskBucket.completed;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: completed, onChanged: (_) => onToggle()),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      task.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: completed
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    if (!completed &&
                        !task.isCancelled &&
                        task.dueAt != null) ...[
                      const SizedBox(height: 7),
                      _DueDatePill(dueAt: task.dueAt!),
                    ],
                    if (task.notes.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        task.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (task.tags.isNotEmpty || task.subtasks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ...task.tags.map((tag) => _TagPill(tag: tag)),
                          if (task.subtasks.isNotEmpty)
                            _ProgressPill(task: task),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: _PriorityPill(priority: task.priority),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KanbanBoard extends StatelessWidget {
  const _KanbanBoard({
    required this.tasks,
    required this.onOpen,
    required this.onMove,
  });

  final List<TodoTask> tasks;
  final ValueChanged<TodoTask> onOpen;
  final void Function(TodoTask, KanbanColumn) onMove;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const minimumBoardWidth = 900.0;
      final boardWidth = constraints.maxWidth < minimumBoardWidth
          ? minimumBoardWidth
          : constraints.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: boardWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final column in KanbanColumn.values)
                Expanded(
                  child: _KanbanLane(
                    column: column,
                    tasks: tasks
                        .where((task) => task.kanbanColumn == column)
                        .toList(),
                    onOpen: onOpen,
                    onMove: onMove,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _KanbanLane extends StatelessWidget {
  const _KanbanLane({
    required this.column,
    required this.tasks,
    required this.onOpen,
    required this.onMove,
  });

  final KanbanColumn column;
  final List<TodoTask> tasks;
  final ValueChanged<TodoTask> onOpen;
  final void Function(TodoTask, KanbanColumn) onMove;

  @override
  Widget build(BuildContext context) {
    final title = switch (column) {
      KanbanColumn.toDo => 'To Do',
      KanbanColumn.inProgress => 'In Progress',
      KanbanColumn.done => 'Done',
    };
    final colors = Theme.of(context).colorScheme;
    return DragTarget<TodoTask>(
      onWillAcceptWithDetails: (details) => details.data.kanbanColumn != column,
      onAcceptWithDetails: (details) => onMove(details.data, column),
      builder: (context, candidates, rejected) => Container(
        margin: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? colors.surfaceContainerLow
              : colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: candidates.isEmpty ? colors.outlineVariant : colors.primary,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                CircleAvatar(
                  radius: 13,
                  backgroundColor: colors.surfaceContainerHighest,
                  child: Text(
                    '${tasks.length}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 40,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No tasks here - drag a card or add one above',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      children: tasks
                          .map(
                            (task) => _KanbanCard(
                              task: task,
                              column: column,
                              onOpen: () => onOpen(task),
                              onMove: (next) => onMove(task, next),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.task,
    required this.column,
    required this.onOpen,
    required this.onMove,
  });

  final TodoTask task;
  final KanbanColumn column;
  final VoidCallback onOpen;
  final ValueChanged<KanbanColumn> onMove;

  @override
  Widget build(BuildContext context) => LongPressDraggable<TodoTask>(
    data: task,
    feedback: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 250,
        child: _KanbanCardContents(task: task, onOpen: onOpen),
      ),
    ),
    childWhenDragging: Opacity(
      opacity: 0.35,
      child: _KanbanCardContents(task: task, onOpen: onOpen),
    ),
    child: _KanbanCardContents(
      task: task,
      onOpen: onOpen,
      onMove: onMove,
      column: column,
    ),
  );
}

class _KanbanCardContents extends StatelessWidget {
  const _KanbanCardContents({
    required this.task,
    required this.onOpen,
    this.onMove,
    this.column,
  });

  final TodoTask task;
  final VoidCallback onOpen;
  final ValueChanged<KanbanColumn>? onMove;
  final KanbanColumn? column;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _PriorityPill(priority: task.priority),
              ],
            ),
            if (task.bucket != TaskBucket.completed &&
                !task.isCancelled &&
                task.dueAt != null) ...[
              const SizedBox(height: 7),
              _DueDatePill(dueAt: task.dueAt!),
            ],
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                task.notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (task.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: task.tags.map((tag) => _TagPill(tag: tag)).toList(),
              ),
            ],
            if (onMove != null && column != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (column!.index > 0)
                    IconButton(
                      tooltip: 'Move left',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          onMove!(KanbanColumn.values[column!.index - 1]),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  if (column!.index < KanbanColumn.values.length - 1)
                    IconButton(
                      tooltip: 'Move right',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          onMove!(KanbanColumn.values[column!.index + 1]),
                      icon: const Icon(Icons.chevron_right),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priority});

  final Priority priority;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, foreground, background) = switch (priority) {
      Priority.high => ('High', colors.error, colors.errorContainer),
      Priority.medium => ('Medium', colors.tertiary, colors.tertiaryContainer),
      Priority.low => ('Low', colors.primary, colors.primaryContainer),
    };
    return _SmallPill(
      label: label,
      foreground: foreground,
      background: background,
      icon: Icons.flag_outlined,
    );
  }
}

class _BucketPill extends StatelessWidget {
  const _BucketPill({required this.bucket});

  final TaskBucket bucket;

  @override
  Widget build(BuildContext context) => _SmallPill(
    label: bucket.name[0].toUpperCase() + bucket.name.substring(1),
    foreground: Theme.of(context).colorScheme.primary,
    background: Theme.of(context).colorScheme.primaryContainer,
    icon: Icons.event_outlined,
  );
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) => _SmallPill(
    label: '#$tag',
    foreground: Theme.of(context).colorScheme.onSurfaceVariant,
    background: Theme.of(context).colorScheme.surfaceContainerHighest,
  );
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.task});

  final TodoTask task;

  @override
  Widget build(BuildContext context) => _SmallPill(
    label: '${task.completedSubtasks}/${task.subtasks.length}',
    foreground: Theme.of(context).colorScheme.primary,
    background: Theme.of(context).colorScheme.primaryContainer,
    icon: Icons.checklist,
  );
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: foreground),
        ),
      ],
    ),
  );
}

class _DueDateControls extends StatelessWidget {
  const _DueDateControls({required this.dueAt, required this.onChanged});

  final DateTime? dueAt;
  final ValueChanged<DateTime?> onChanged;

  void _setDay(int offset) {
    final now = DateTime.now();
    final current = dueAt?.toLocal() ?? now;
    onChanged(
      DateTime(
        now.year,
        now.month,
        now.day + offset,
        current.hour,
        current.minute,
      ).toUtc(),
    );
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final now = DateTime.now();
    final current = dueAt?.toLocal() ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !context.mounted) return;
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute).toUtc(),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (dueAt != null)
          _DueDatePill(dueAt: dueAt!)
        else
          Text(
            'No due date',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ActionChip(label: const Text('Today'), onPressed: () => _setDay(0)),
        ActionChip(label: const Text('Tomorrow'), onPressed: () => _setDay(1)),
        ActionChip(
          avatar: const Icon(Icons.calendar_month_outlined, size: 16),
          label: const Text('Pick Date & Time'),
          onPressed: () => _pickDateTime(context),
        ),
        if (dueAt != null)
          ActionChip(
            label: const Text('Clear'),
            onPressed: () => onChanged(null),
          ),
      ],
    ),
  );
}

class _DueDatePill extends StatelessWidget {
  const _DueDatePill({required this.dueAt});

  final DateTime dueAt;

  @override
  Widget build(BuildContext context) {
    final remaining = dueAt.toUtc().difference(DateTime.now().toUtc());
    final (label, foreground, background, icon) = remaining.isNegative
        ? (
            'Past Due',
            const Color(0xFF8A1C1C),
            const Color(0xFFFFE6E3),
            Icons.error_outline,
          )
        : remaining <= const Duration(hours: 24)
        ? (
            'Due Soon',
            const Color(0xFF704600),
            const Color(0xFFFFF0C2),
            Icons.schedule,
          )
        : (
            'Upcoming',
            const Color(0xFF17613A),
            const Color(0xFFE0F3E7),
            Icons.event_available_outlined,
          );
    return _SmallPill(
      label: '$label · ${_formatShortDateTime(dueAt)}',
      foreground: foreground,
      background: background,
      icon: icon,
    );
  }
}

class _CancelledTaskCard extends StatelessWidget {
  const _CancelledTaskCard({required this.task, required this.onRestore});

  final TodoTask task;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFF762D42);
    const background = Color(0xFFFFF0F2);
    final cancelledAt = task.cancelledAt;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5AAB8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: foreground),
                  ),
                ),
                const _SmallPill(
                  label: 'Cancelled',
                  foreground: foreground,
                  background: Color(0xFFF4D5DC),
                  icon: Icons.cancel_outlined,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cancelled: ${cancelledAt == null ? 'Timestamp unavailable' : _formatCancelledDateTime(cancelledAt)}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: foreground),
            ),
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore),
                label: const Text('Restore Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatClock(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $suffix';
}

String _formatShortDateTime(DateTime time) {
  final local = time.toLocal();
  return '${_monthNames[local.month - 1]} ${local.day}, ${_formatClock(local)}';
}

String _formatCancelledDateTime(DateTime time) {
  final local = time.toLocal();
  return '${_monthNames[local.month - 1]} ${local.day}, ${local.year} at ${_formatClock(local)}';
}

DateTime _calendarDate(DateTime date, [int dayOffset = 0]) =>
    DateTime(date.year, date.month, date.day + dayOffset);

String _calendarDateKey(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _weekdayLabel(DateTime date) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];

String _shortCalendarLabel(DateTime date) =>
    '${_monthNames[date.month - 1]} ${date.day}';

String _fullCalendarLabel(DateTime date) =>
    '${_weekdayLabel(date)}, ${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

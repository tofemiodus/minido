import 'dart:convert';

enum Priority { high, medium, low }

enum TaskBucket { today, upcoming, completed }

enum KanbanColumn { toDo, inProgress, done }

class Subtask {
  const Subtask({required this.id, required this.title, this.isDone = false});

  final String id;
  final String title;
  final bool isDone;

  Subtask copyWith({String? title, bool? isDone}) => Subtask(
    id: id,
    title: title ?? this.title,
    isDone: isDone ?? this.isDone,
  );

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'isDone': isDone};

  static Subtask fromJson(Object? value) {
    final map = _asMap(value, 'subtask');
    return Subtask(
      id: _requiredString(map, 'id', 'subtask'),
      title: _requiredString(map, 'title', 'subtask'),
      isDone: _optionalBool(map, 'isDone', false, 'subtask'),
    );
  }
}

class TodoTask {
  TodoTask({
    required this.id,
    required this.title,
    this.notes = '',
    this.priority = Priority.medium,
    this.bucket = TaskBucket.upcoming,
    this.kanbanColumn = KanbanColumn.toDo,
    this.tags = const [],
    this.subtasks = const [],
    DateTime? updatedAt,
    this.isCancelled = false,
    bool isFocus = false,
    this.dueAt,
    this.cancelledAt,
    this.completedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc(),
       isFocus = isFocus && !isCancelled && bucket != TaskBucket.completed;

  final String id;
  final String title;
  final String notes;
  final Priority priority;
  final TaskBucket bucket;
  final KanbanColumn kanbanColumn;
  final List<String> tags;
  final List<Subtask> subtasks;
  final DateTime updatedAt;
  final bool isCancelled;
  final bool isFocus;
  final DateTime? dueAt;
  final DateTime? cancelledAt;
  final DateTime? completedAt;

  bool get isSample => id.startsWith('sample-');
  bool get isCompleted => bucket == TaskBucket.completed;
  int get completedSubtasks =>
      subtasks.where((subtask) => subtask.isDone).length;

  TodoTask copyWith({
    String? title,
    String? notes,
    Priority? priority,
    TaskBucket? bucket,
    KanbanColumn? kanbanColumn,
    List<String>? tags,
    List<Subtask>? subtasks,
    DateTime? updatedAt,
    bool? isCancelled,
    bool? isFocus,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? cancelledAt,
    bool clearCancelledAt = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) => TodoTask(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    priority: priority ?? this.priority,
    bucket: bucket ?? this.bucket,
    kanbanColumn: kanbanColumn ?? this.kanbanColumn,
    tags: tags ?? this.tags,
    subtasks: subtasks ?? this.subtasks,
    updatedAt: updatedAt ?? this.updatedAt,
    isCancelled: isCancelled ?? this.isCancelled,
    isFocus: isFocus ?? this.isFocus,
    dueAt: clearDueAt ? null : dueAt ?? this.dueAt,
    cancelledAt: clearCancelledAt ? null : cancelledAt ?? this.cancelledAt,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'priority': priority.name,
    'bucket': bucket.name,
    'kanbanColumn': kanbanColumn.name,
    'tags': tags,
    'subtasks': subtasks.map((subtask) => subtask.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'isCancelled': isCancelled,
    'isFocus': isFocus,
    'dueAt': dueAt?.toIso8601String(),
    'cancelledAt': cancelledAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  static TodoTask fromJson(Object? value) {
    final map = _asMap(value, 'task');
    final tagsValue = map['tags'];
    final subtasksValue = map['subtasks'];
    if (tagsValue is! List<Object?> || subtasksValue is! List<Object?>) {
      throw const FormatException(
        'Each task must contain tags and subtasks arrays.',
      );
    }

    final tags = tagsValue.map((tag) {
      if (tag is! String || tag.trim().isEmpty) {
        throw const FormatException('Task tags must be non-empty strings.');
      }
      return tag.trim();
    }).toList();

    return TodoTask(
      id: _requiredString(map, 'id', 'task'),
      title: _requiredString(map, 'title', 'task'),
      notes: _optionalString(map, 'notes', '', 'task'),
      priority: _enumValue(Priority.values, map['priority'], 'priority'),
      bucket: _enumValue(TaskBucket.values, map['bucket'], 'bucket'),
      kanbanColumn: _enumValue(
        KanbanColumn.values,
        map['kanbanColumn'],
        'kanbanColumn',
      ),
      tags: tags,
      subtasks: subtasksValue.map(Subtask.fromJson).toList(),
      updatedAt: _optionalDateTime(map, 'updatedAt') ?? DateTime.now().toUtc(),
      isCancelled: _optionalBool(map, 'isCancelled', false, 'task'),
      isFocus: _optionalBool(map, 'isFocus', false, 'task'),
      dueAt: _optionalDateTime(map, 'dueAt'),
      cancelledAt: _optionalDateTime(map, 'cancelledAt'),
      completedAt: _optionalDateTime(map, 'completedAt'),
    );
  }
}

class BackupDocument {
  const BackupDocument({required this.tasks, this.themeMode = 'light'});

  final List<TodoTask> tasks;
  final String themeMode;

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'themeMode': themeMode,
    'tasks': tasks.map((task) => task.toJson()).toList(),
  });

  static BackupDocument fromJsonString(String source) {
    final decoded = jsonDecode(source);
    final map = _asMap(decoded, 'backup');
    if (map['schemaVersion'] != 1) {
      throw const FormatException('Unsupported backup schema version.');
    }
    final tasksValue = map['tasks'];
    if (tasksValue is! List<Object?>) {
      throw const FormatException('The backup must contain a tasks array.');
    }
    final themeMode = map['themeMode'];
    if (themeMode != 'light' && themeMode != 'dark') {
      throw const FormatException(
        'The backup themeMode must be "light" or "dark".',
      );
    }

    final tasks = tasksValue.map(TodoTask.fromJson).toList();
    final ids = <String>{};
    for (final task in tasks) {
      if (!ids.add(task.id)) {
        throw const FormatException('The backup contains duplicate task IDs.');
      }
    }
    return BackupDocument(tasks: tasks, themeMode: themeMode as String);
  }
}

class QuickAddDraft {
  const QuickAddDraft({
    required this.title,
    required this.priority,
    required this.tags,
    required this.bucket,
  });

  final String title;
  final Priority priority;
  final List<String> tags;
  final TaskBucket bucket;
}

QuickAddDraft parseQuickAdd(
  String input, {
  TaskBucket defaultBucket = TaskBucket.today,
}) {
  var title = input;
  var priority = Priority.medium;
  final priorityPattern = RegExp(
    r'!(high|med(?:ium)?|low)\b',
    caseSensitive: false,
  );
  for (final match in priorityPattern.allMatches(input)) {
    priority = switch (match.group(1)!.toLowerCase()) {
      'high' => Priority.high,
      'med' || 'medium' => Priority.medium,
      'low' => Priority.low,
      _ => priority,
    };
  }
  title = title.replaceAll(priorityPattern, ' ');

  final tags = <String>[];
  final tagPattern = RegExp(r'#([A-Za-z0-9_-]+)');
  for (final match in tagPattern.allMatches(title)) {
    final tag = match.group(1)!.toLowerCase();
    if (!tags.contains(tag)) tags.add(tag);
  }
  title = title.replaceAll(tagPattern, ' ');

  final hasTomorrow = RegExp(
    r'\btomorrow\b',
    caseSensitive: false,
  ).hasMatch(title);
  final hasToday = RegExp(r'\btoday\b', caseSensitive: false).hasMatch(title);
  final bucket = hasTomorrow
      ? TaskBucket.upcoming
      : hasToday
      ? TaskBucket.today
      : defaultBucket;
  title = title
      .replaceAll(RegExp(r'\b(?:today|tomorrow)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return QuickAddDraft(
    title: title,
    priority: priority,
    tags: tags,
    bucket: bucket,
  );
}

Map<String, Object?> _asMap(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('The $label must be a JSON object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('The $label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> map, String key, String label) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'The $label field "$key" must be a non-empty string.',
    );
  }
  return value.trim();
}

String _optionalString(
  Map<String, Object?> map,
  String key,
  String defaultValue,
  String label,
) {
  final value = map[key];
  if (value == null) return defaultValue;
  if (value is! String) {
    throw FormatException('The $label field "$key" must be a string.');
  }
  return value;
}

bool _optionalBool(
  Map<String, Object?> map,
  String key,
  bool defaultValue,
  String label,
) {
  final value = map[key];
  if (value == null) return defaultValue;
  if (value is! bool) {
    throw FormatException('The $label field "$key" must be a boolean.');
  }
  return value;
}

DateTime? _optionalDateTime(
  Map<String, Object?> map,
  String key, {
  String? label,
}) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('The ${label ?? key} must be a date-time string.');
  }
  return DateTime.parse(value).toUtc();
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String label) {
  if (value is! String) {
    throw FormatException('The "$label" field must be a string.');
  }
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('Unknown "$label" value: $value.');
}

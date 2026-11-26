import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:minido/main.dart';
import 'package:minido/models/task_models.dart';
import 'package:minido/data/task_store.dart';

void main() {
  group('quick add parsing', () {
    test('extracts priority, tags, and tomorrow bucket from the title', () {
      final draft = parseQuickAdd(
        'Call Sam tomorrow !high #Work #family',
        defaultBucket: TaskBucket.today,
      );

      expect(draft.title, 'Call Sam');
      expect(draft.priority, Priority.high);
      expect(draft.tags, ['work', 'family']);
      expect(draft.bucket, TaskBucket.upcoming);
    });

    test('accepts medium aliases and strips today', () {
      final draft = parseQuickAdd('Pay rent !medium today');

      expect(draft.title, 'Pay rent');
      expect(draft.priority, Priority.medium);
      expect(draft.bucket, TaskBucket.today);
    });
  });

  group('backup validation', () {
    test('round-trips tasks, subtasks, and theme mode', () {
      final document = BackupDocument(
        themeMode: 'dark',
        tasks: [
          TodoTask(
            id: 'task-1',
            title: 'Review notes',
            priority: Priority.high,
            bucket: TaskBucket.today,
            kanbanColumn: KanbanColumn.inProgress,
            isFocus: true,
            tags: ['work'],
            subtasks: [
              Subtask(id: 'subtask-1', title: 'Open notebook', isDone: true),
            ],
          ),
        ],
      );

      final restored = BackupDocument.fromJsonString(document.toPrettyJson());

      expect(restored.themeMode, 'dark');
      expect(restored.tasks.single.title, 'Review notes');
      expect(restored.tasks.single.subtasks.single.isDone, isTrue);
      expect(restored.tasks.single.kanbanColumn, KanbanColumn.inProgress);
      expect(restored.tasks.single.isFocus, isTrue);
    });

    test('rejects malformed structure and unsupported schema', () {
      expect(
        () => BackupDocument.fromJsonString('{"schemaVersion":1,"tasks":[{}]}'),
        throwsFormatException,
      );
      expect(
        () => BackupDocument.fromJsonString(
          '{"schemaVersion":9,"themeMode":"light","tasks":[]}',
        ),
        throwsFormatException,
      );
      expect(
        () => BackupDocument.fromJsonString('{not json'),
        throwsFormatException,
      );
    });
  });

  testWidgets('first launch seeds sample tasks and can clear them', (
    tester,
  ) async {
    final store = MemoryTaskStore();
    await tester.pumpWidget(MinidoApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Plan the week'), findsOneWidget);
    expect(find.text('Clear sample data'), findsOneWidget);
    final seeded = BackupDocument.fromJsonString(store.value!);
    expect(seeded.tasks, hasLength(4));
    expect(
      seeded.tasks.map((task) => task.bucket).toSet(),
      containsAll(TaskBucket.values),
    );
    expect(seeded.tasks.first.subtasks, hasLength(3));

    await tester.tap(find.text('Clear sample data'));
    await tester.pumpAndSettle();

    expect(find.text('Plan the week'), findsNothing);
    expect(find.text('Clear sample data'), findsNothing);
    expect(BackupDocument.fromJsonString(store.value!).tasks, isEmpty);
  });

  testWidgets('invalid imported JSON shows an error and keeps local tasks', (
    tester,
  ) async {
    final store = MemoryTaskStore();
    await tester.pumpWidget(MinidoApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Backup and restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '{bad json');
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid backup:'), findsOneWidget);
    expect(BackupDocument.fromJsonString(store.value!).tasks, hasLength(4));
  });
}

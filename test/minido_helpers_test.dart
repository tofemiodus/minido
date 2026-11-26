import 'package:flutter_test/flutter_test.dart';
import 'package:minido/models/task_models.dart';
import 'package:minido/utils/minido_helpers.dart';

void main() {
  test('snooze defaults to tomorrow at 5pm and advances past due times', () {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final noDueDate = MinidoSnooze.tomorrow(null);
    expect(noDueDate.year, tomorrow.year);
    expect(noDueDate.month, tomorrow.month);
    expect(noDueDate.day, tomorrow.day);
    expect(noDueDate.hour, 17);
    expect(noDueDate.minute, 0);

    final pastDue = DateTime(now.year, now.month, now.day - 1, 9, 25);
    final snoozedPast = MinidoSnooze.tomorrow(pastDue);
    expect(snoozedPast.year, tomorrow.year);
    expect(snoozedPast.month, tomorrow.month);
    expect(snoozedPast.day, tomorrow.day);
    expect(snoozedPast.hour, 9);
    expect(snoozedPast.minute, 25);

    final futureDue = now.add(const Duration(hours: 4));
    expect(
      MinidoSnooze.tomorrow(futureDue),
      futureDue.add(const Duration(days: 1)),
    );
  });

  test('focus cap and undo snapshots behave as expected', () {
    expect(MinidoFocus.canAdd(2), isTrue);
    expect(MinidoFocus.canAdd(3), isFalse);
    expect(MinidoFocus.fullMsg, contains('capped at 3'));

    final source = <Map<String, Object?>>[
      {
        'title': 'Task',
        'tags': ['home'],
      },
    ];
    final copy = MinidoUndo.clone(source);
    (copy.single['tags']! as List<Object?>).add('work');
    expect(source.single['tags'], ['home']);
  });

  test('legacy task backups default Today Focus to false', () {
    final task = TodoTask.fromJson({
      'id': 'legacy',
      'title': 'Older backup',
      'priority': 'medium',
      'bucket': 'today',
      'kanbanColumn': 'toDo',
      'tags': <String>[],
      'subtasks': <Object>[],
    });

    expect(task.isFocus, isFalse);
  });

  test('completed and cancelled tasks cannot remain in Today Focus', () {
    final completed = TodoTask(
      id: 'completed',
      title: 'Done',
      bucket: TaskBucket.completed,
      isFocus: true,
    );
    final cancelled = TodoTask(
      id: 'cancelled',
      title: 'Cancelled',
      isCancelled: true,
      isFocus: true,
    );

    expect(completed.isFocus, isFalse);
    expect(cancelled.isFocus, isFalse);
  });
}

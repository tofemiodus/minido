part of '../../main.dart';

class _DailyCompletion {
  const _DailyCompletion({required this.date, required this.count});

  final DateTime date;
  final int count;
}

class _StatisticsView extends StatelessWidget {
  const _StatisticsView({
    required this.tasks,
    required this.periodDays,
    required this.onPeriodChanged,
  });

  final List<TodoTask> tasks;
  final int periodDays;
  final ValueChanged<int> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final today = _calendarDate(DateTime.now());
    final completionCounts = <String, int>{};
    for (final task in tasks) {
      if (!task.isCompleted || task.isCancelled) continue;
      final completionDate = (task.completedAt ?? task.updatedAt).toLocal();
      final key = _calendarDateKey(completionDate);
      completionCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }

    final days = [
      for (var offset = periodDays - 1; offset >= 0; offset--)
        _DailyCompletion(
          date: _calendarDate(today, -offset),
          count:
              completionCounts[_calendarDateKey(
                _calendarDate(today, -offset),
              )] ??
              0,
        ),
    ];
    final periodTotal = days.fold<int>(0, (total, day) => total + day.count);
    final completedToday = completionCounts[_calendarDateKey(today)] ?? 0;
    final currentStreak = _calculateCurrentStreak(today, completionCounts);
    final hasCompletions = completionCounts.isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Statistics',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Tasks completed each day',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('Last 7 Days')),
                  ButtonSegment(value: 30, label: Text('Last 30 Days')),
                ],
                selected: {periodDays},
                onSelectionChanged: (selection) =>
                    onPeriodChanged(selection.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 720
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _StatisticsSummaryCard(
                      title: 'Completed Today',
                      value: '$completedToday',
                      icon: Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _StatisticsSummaryCard(
                      title: 'Period Total',
                      value: '$periodTotal',
                      icon: Icons.bar_chart_outlined,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _StatisticsSummaryCard(
                      title: 'Current Streak',
                      value:
                          '$currentStreak ${currentStreak == 1 ? 'day' : 'days'}',
                      icon: Icons.local_fire_department_outlined,
                      color: const Color(0xFFB05A18),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _DailyCompletionChart(days: days, periodDays: periodDays),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Daily breakdown',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (!hasCompletions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No completed tasks yet. Complete a task to start your daily progress.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final day in days.reversed)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_fullCalendarLabel(day.date)),
                        trailing: Text(
                          '${day.count}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

int _calculateCurrentStreak(DateTime today, Map<String, int> counts) {
  var currentDate = today;
  if ((counts[_calendarDateKey(currentDate)] ?? 0) == 0) {
    currentDate = _calendarDate(today, -1);
    if ((counts[_calendarDateKey(currentDate)] ?? 0) == 0) return 0;
  }

  var streak = 0;
  while ((counts[_calendarDateKey(currentDate)] ?? 0) > 0) {
    streak++;
    currentDate = _calendarDate(currentDate, -1);
  }
  return streak;
}

class _StatisticsSummaryCard extends StatelessWidget {
  const _StatisticsSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DailyCompletionChart extends StatelessWidget {
  const _DailyCompletionChart({required this.days, required this.periodDays});

  final List<_DailyCompletion> days;
  final int periodDays;

  @override
  Widget build(BuildContext context) {
    final maximum = days.fold<int>(
      0,
      (current, day) => day.count > current ? day.count : current,
    );
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tasks Completed Each Day',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final minimumWidth = days.length * 38.0;
                final chartWidth = constraints.maxWidth > minimumWidth
                    ? constraints.maxWidth
                    : minimumWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    height: 236,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final day in days)
                          Expanded(
                            child: Tooltip(
                              message:
                                  '${_fullCalendarLabel(day.date)}: ${day.count} completed ${day.count == 1 ? 'task' : 'tasks'}',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 22,
                                      child: Center(
                                        child: Text(
                                          '${day.count}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, barConstraints) {
                                          final ratio = maximum == 0
                                              ? 0.0
                                              : day.count / maximum;
                                          final barHeight = ratio == 0
                                              ? 0.0
                                              : (barConstraints.maxHeight *
                                                        ratio)
                                                    .clamp(
                                                      4.0,
                                                      barConstraints.maxHeight,
                                                    )
                                                    .toDouble();
                                          return Container(
                                            width: 18,
                                            height: barConstraints.maxHeight,
                                            decoration: BoxDecoration(
                                              color: colors
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                            ),
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              width: 18,
                                              height: barHeight,
                                              decoration: BoxDecoration(
                                                color: colors.primary,
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      height: 24,
                                      child: Center(
                                        child: Text(
                                          periodDays == 7
                                              ? _weekdayLabel(day.date)
                                              : _shortCalendarLabel(day.date),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

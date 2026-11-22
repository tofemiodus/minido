part of '../../main.dart';

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _controller = TextEditingController();
  String? _mode; // 'merge' | 'replace'
  String? _fileError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _controller.text = utf8.decode(bytes);
        _fileError = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _fileError = 'Could not open file: $error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import backup'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste a Minido JSON backup or choose a .json file.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose JSON file'),
            ),
            if (_fileError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _fileError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'merge',
                  label: Text('Merge with current list'),
                ),
                ButtonSegment(
                  value: 'replace',
                  label: Text('Replace all tasks'),
                ),
              ],
              selected: {_mode ?? 'merge'},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              minLines: 8,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: '{ "version": 1, "tasks": [...] }',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _ImportResult(_controller.text, _mode == 'replace'),
        ),
        child: const Text('Restore backup'),
      ),
    ],
  );
}

String _priorityName(Priority priority) => switch (priority) {
  Priority.high => 'High',
  Priority.medium => 'Medium',
  Priority.low => 'Low',
};

String _bucketName(TaskBucket bucket) => switch (bucket) {
  TaskBucket.today => 'Today',
  TaskBucket.upcoming => 'Upcoming',
  TaskBucket.completed => 'Completed',
};

String _columnName(KanbanColumn column) => switch (column) {
  KanbanColumn.toDo => 'To Do',
  KanbanColumn.inProgress => 'In Progress',
  KanbanColumn.done => 'Done',
};

class _ImportResult {
  const _ImportResult(this.source, this.replaceAll);
  final String source;
  final bool replaceAll;
}

List<TodoTask> _parseImportedTasks(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('The import must be a JSON object.');
  }
  final tasksValue = decoded['tasks'];
  if (tasksValue is! List) {
    throw const FormatException('The import must contain a tasks array.');
  }
  return tasksValue.map((task) => TodoTask.fromJson(task)).toList();
}

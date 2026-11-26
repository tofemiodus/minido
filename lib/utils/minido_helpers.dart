import 'dart:convert';

import 'package:material_ui/material_ui.dart';

class MinidoResponsive {
  const MinidoResponsive._();

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  static double pad(BuildContext context) => isCompact(context) ? 12 : 24;

  static const double tapTarget = 44;
}

class MinidoSnooze {
  const MinidoSnooze._();

  static DateTime tomorrow(DateTime? due) {
    if (due == null) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day + 1, 17);
    }

    final now = DateTime.now();
    if (due.isBefore(now)) {
      final localDue = due.toLocal();
      return DateTime(
        now.year,
        now.month,
        now.day + 1,
        localDue.hour,
        localDue.minute,
      );
    }
    return due.add(const Duration(days: 1));
  }
}

class MinidoFocus {
  const MinidoFocus._();

  static const int max = 3;
  static bool canAdd(int count) => count < max;
  static const String fullMsg =
      'Today Focus is capped at 3 tasks. Unstar one first.';
}

class MinidoUndo {
  const MinidoUndo({required this.label, required this.snapshot});

  final String label;
  final List<Map<String, Object?>> snapshot;

  static List<Map<String, Object?>> clone(List<Map<String, Object?>> list) {
    final decoded = jsonDecode(jsonEncode(list)) as List<Object?>;
    return decoded
        .map((item) => (item as Map<Object?, Object?>).cast<String, Object?>())
        .toList();
  }
}

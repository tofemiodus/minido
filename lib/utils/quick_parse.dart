// Pure local Dart regex parser — zero network, zero AI.
// Extracts a clean task title + optional DateTime + matched phrase.

class QuickParseResult {
  const QuickParseResult({
    required this.cleanTitle,
    this.dateTime,
    this.matchedPhrase,
  });

  final String cleanTitle;
  final DateTime? dateTime;
  final String? matchedPhrase;

  bool get hasDate => dateTime != null;
}

/// Parses natural-language date/time tokens out of [input] and returns a
/// [QuickParseResult] with the remaining clean title and the parsed [DateTime].
QuickParseResult quickParse(String input) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // Try each pattern in priority order; first match wins.
  for (final _Parser p in _parsers) {
    final result = p(input, now, today);
    if (result != null) return result;
  }

  // No date/time detected.
  return QuickParseResult(cleanTitle: input.trim());
}

// ─── helpers ────────────────────────────────────────────────────────────────

typedef _Parser = QuickParseResult? Function(
  String input,
  DateTime now,
  DateTime today,
);

String _strip(String input, String phrase) =>
    input.replaceFirst(phrase, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

/// Apply a detected time-of-day to a base date.
DateTime _withTime(DateTime base, int hour, int minute) =>
    DateTime(base.year, base.month, base.day, hour, minute);

/// Parse a trailing or leading time token like `4pm`, `4:30pm`, `16:00`.
/// Returns `null` if no time is found.
(int hour, int minute, String phrase)? _extractTime(String text) {
  final re = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b'
    r'|\b([01]?\d|2[0-3]):([0-5]\d)\b',
    caseSensitive: false,
  );
  final m = re.firstMatch(text);
  if (m == null) return null;

  int hour;
  int minute;
  String phrase;

  if (m.group(3) != null) {
    // 12-hour format with am/pm
    hour = int.parse(m.group(1)!);
    minute = m.group(2) != null ? int.parse(m.group(2)!) : 0;
    final ampm = m.group(3)!.toLowerCase();
    if (ampm == 'pm' && hour != 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;
    phrase = m.group(0)!;
  } else {
    // 24-hour format
    hour = int.parse(m.group(4)!);
    minute = int.parse(m.group(5)!);
    phrase = m.group(0)!;
  }

  return (hour, minute, phrase);
}

// ─── individual parsers ──────────────────────────────────────────────────────

final List<_Parser> _parsers = [
  // "in Xm" / "in Xh" / "in Xd"
  (input, now, _) {
    final re = RegExp(
      r'\bin\s+(\d+)\s*(m(?:in(?:ute)?s?)?|h(?:ours?)?|d(?:ays?)?)\b',
      caseSensitive: false,
    );
    final m = re.firstMatch(input);
    if (m == null) return null;
    final amount = int.parse(m.group(1)!);
    final unit = m.group(2)![0].toLowerCase();
    final Duration delta;
    switch (unit) {
      case 'm':
        delta = Duration(minutes: amount);
      case 'h':
        delta = Duration(hours: amount);
      default:
        delta = Duration(days: amount);
    }
    final dt = now.add(delta);
    return QuickParseResult(
      cleanTitle: _strip(input, m.group(0)!),
      dateTime: dt,
      matchedPhrase: m.group(0),
    );
  },

  // "tonight" → today at 20:00
  (input, now, today) {
    final re = RegExp(r'\btonight\b', caseSensitive: false);
    final m = re.firstMatch(input);
    if (m == null) return null;
    // Check for extra time token
    final stripped = _strip(input, m.group(0)!);
    final timeData = _extractTime(stripped);
    final DateTime dt;
    final String phrase;
    if (timeData != null) {
      final (h, min, tp) = timeData;
      dt = _withTime(today, h, min);
      phrase = '${m.group(0)!} $tp'.trim();
    } else {
      dt = _withTime(today, 20, 0);
      phrase = m.group(0)!;
    }
    return QuickParseResult(
      cleanTitle: timeData != null ? _strip(stripped, timeData.$3) : stripped,
      dateTime: dt,
      matchedPhrase: phrase,
    );
  },

  // "today"
  (input, now, today) {
    final re = RegExp(r'\btoday\b', caseSensitive: false);
    final m = re.firstMatch(input);
    if (m == null) return null;
    final stripped = _strip(input, m.group(0)!);
    final timeData = _extractTime(stripped);
    final DateTime dt;
    final String phrase;
    if (timeData != null) {
      final (h, min, tp) = timeData;
      dt = _withTime(today, h, min);
      phrase = '${m.group(0)!} $tp'.trim();
    } else {
      dt = _withTime(today, now.hour, now.minute).add(const Duration(hours: 1));
      phrase = m.group(0)!;
    }
    return QuickParseResult(
      cleanTitle: timeData != null ? _strip(stripped, timeData.$3) : stripped,
      dateTime: dt,
      matchedPhrase: phrase,
    );
  },

  // "tmr" / "tomorrow"
  (input, now, today) {
    final re = RegExp(r'\b(?:tmr|tomorrow)\b', caseSensitive: false);
    final m = re.firstMatch(input);
    if (m == null) return null;
    final base = today.add(const Duration(days: 1));
    final stripped = _strip(input, m.group(0)!);
    final timeData = _extractTime(stripped);
    final DateTime dt;
    final String phrase;
    if (timeData != null) {
      final (h, min, tp) = timeData;
      dt = _withTime(base, h, min);
      phrase = '${m.group(0)!} $tp'.trim();
    } else {
      dt = _withTime(base, 9, 0);
      phrase = m.group(0)!;
    }
    return QuickParseResult(
      cleanTitle: timeData != null ? _strip(stripped, timeData.$3) : stripped,
      dateTime: dt,
      matchedPhrase: phrase,
    );
  },

  // Weekday names: mon/tue/wed/thu/fri/sat/sun (next occurrence)
  (input, now, today) {
    final re = RegExp(
      r'\b(mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b',
      caseSensitive: false,
    );
    final m = re.firstMatch(input);
    if (m == null) return null;
    const weekdayMap = {
      'mon': 1,
      'tue': 2,
      'wed': 3,
      'thu': 4,
      'fri': 5,
      'sat': 6,
      'sun': 7,
    };
    final key = m.group(1)!.toLowerCase().substring(0, 3);
    final targetWeekday = weekdayMap[key]!;
    var daysAhead = targetWeekday - today.weekday;
    if (daysAhead <= 0) daysAhead += 7;
    final base = today.add(Duration(days: daysAhead));
    final stripped = _strip(input, m.group(0)!);
    final timeData = _extractTime(stripped);
    final DateTime dt;
    final String phrase;
    if (timeData != null) {
      final (h, min, tp) = timeData;
      dt = _withTime(base, h, min);
      phrase = '${m.group(0)!} $tp'.trim();
    } else {
      dt = _withTime(base, 9, 0);
      phrase = m.group(0)!;
    }
    return QuickParseResult(
      cleanTitle: timeData != null ? _strip(stripped, timeData.$3) : stripped,
      dateTime: dt,
      matchedPhrase: phrase,
    );
  },

  // Standalone time (e.g. "4pm", "4:30 pm", "16:00") — assumes today
  (input, now, today) {
    final timeData = _extractTime(input);
    if (timeData == null) return null;
    final (h, min, phrase) = timeData;
    final dt = _withTime(today, h, min);
    return QuickParseResult(
      cleanTitle: _strip(input, phrase),
      dateTime: dt,
      matchedPhrase: phrase,
    );
  },
];

import 'package:intl/intl.dart';

/// Result of parsing a quick-capture line like "study graphs tomorrow 7pm".
class QuickCapture {
  const QuickCapture({required this.title, this.due, this.hasTime = false});

  final String title;
  final DateTime? due;
  final bool hasTime;

  String? get dueLabel {
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due!.year, due!.month, due!.day);
    final diff = day.difference(today).inDays;
    final dayText = switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => DateFormat('EEE, d MMM').format(due!),
    };
    return hasTime ? '$dayText, ${DateFormat('h:mm a').format(due!)}' : dayText;
  }
}

/// Rule-based parser — the first step before any AI call.
/// See ARCHITECTURE.md §12.2. Handles: today / tomorrow / weekday names,
/// and times like 7pm, 7:30 pm, 19:00.
abstract final class QuickCaptureParser {
  static final _time = RegExp(r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b', caseSensitive: false);
  static const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

  static QuickCapture parse(String input, {DateTime? now}) {
    now ??= DateTime.now();
    var text = ' ${input.trim()} ';
    DateTime? date;

    if (RegExp(r'\btomorrow\b', caseSensitive: false).hasMatch(text)) {
      date = DateTime(now.year, now.month, now.day + 1);
      text = text.replaceAll(RegExp(r'\btomorrow\b', caseSensitive: false), ' ');
    } else if (RegExp(r'\btoday\b|\btonight\b', caseSensitive: false).hasMatch(text)) {
      date = DateTime(now.year, now.month, now.day);
      text = text.replaceAll(RegExp(r'\btoday\b|\btonight\b', caseSensitive: false), ' ');
    } else {
      for (var i = 0; i < 7; i++) {
        final re = RegExp('\\b(on\\s+)?${_weekdays[i]}\\b', caseSensitive: false);
        if (re.hasMatch(text)) {
          var ahead = (i + 1 - now.weekday) % 7;
          if (ahead == 0) ahead = 7;
          date = DateTime(now.year, now.month, now.day + ahead);
          text = text.replaceAll(re, ' ');
          break;
        }
      }
    }

    var hasTime = false;
    final m = _time.allMatches(text).where((m) {
      // only accept numbers that look like times (have am/pm or minutes)
      return m.group(3) != null || m.group(2) != null;
    }).firstOrNull;
    if (m != null) {
      var hour = int.parse(m.group(1)!);
      final minute = int.tryParse(m.group(2) ?? '0') ?? 0;
      final ampm = m.group(3)?.toLowerCase();
      if (ampm == 'pm' && hour < 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;
      if (hour < 24 && minute < 60) {
        date ??= DateTime(now.year, now.month, now.day);
        date = DateTime(date.year, date.month, date.day, hour, minute);
        hasTime = true;
        text = text.replaceRange(m.start, m.end, ' ');
      }
    }

    final title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return QuickCapture(
      title: title.isEmpty ? input.trim() : '${title[0].toUpperCase()}${title.substring(1)}',
      due: date,
      hasTime: hasTime,
    );
  }
}

import 'package:intl/intl.dart';

import '../../../data/models/sprint.dart';

/// Small pure helpers the sprint widgets share. Kept apart from any one
/// widget so the move sheet, the grid, the chip strip and the header all
/// spell a sprint the same way, and so each is testable on its own.

/// Key identifying a row in a chip strip or a collapse set. The Unparented
/// row has no work item, so it needs a name of its own (r2 §5.3).
const String kUnparentedRowKey = 'unparented';

String sprintRowKey(SprintRow row) =>
    row.parent == null ? kUnparentedRowKey : '${row.parent!.id}';

/// Remaining work as the taskboard writes it: `12 h`, `1.5 h`, and nothing
/// at all when the team does not fill the field in (research/18 §1 — that
/// is every team probed, so an empty string has to read well).
String formatRemaining(double? hours) {
  if (hours == null || hours <= 0) return '';
  final rounded = (hours * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return '$text h';
}

/// `No tasks`, `1 task`, `4 tasks`.
String formatTaskCount(int count) => switch (count) {
  0 => 'No tasks',
  1 => '1 task',
  _ => '$count tasks',
};

/// `3–14 Nov`, `28 Dec – 8 Jan`, `3 Nov 2025 – 8 Jan 2026`, or
/// `Dates not set`: iteration dates are legal nulls (research/18 S11) and
/// they are date-only, so nothing here shifts them into a local time zone.
String sprintDateRange(DateTime? start, DateTime? finish) {
  if (start == null && finish == null) return 'Dates not set';
  final day = DateFormat('d');
  final dayMonth = DateFormat('d MMM');
  final full = DateFormat('d MMM y');
  if (start == null) return 'Ends ${full.format(finish!)}';
  if (finish == null) return 'Starts ${full.format(start)}';
  if (start.year != finish.year) {
    return '${full.format(start)} – ${full.format(finish)}';
  }
  if (start.month == finish.month) {
    return '${day.format(start)}–${dayMonth.format(finish)}';
  }
  return '${dayMonth.format(start)} – ${dayMonth.format(finish)}';
}

/// How many whole days are left of the sprint, or null when it has no end
/// date. Negative once the finish date has passed.
int? sprintDaysLeft(DateTime? finish, {DateTime? now}) {
  if (finish == null) return null;
  final today = now ?? DateTime.now();
  return DateTime(
    finish.year,
    finish.month,
    finish.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
}

/// `Ended 3 days ago` for an iteration the service still calls current
/// (research/18 S12). No day count when the dates are missing.
String sprintEndedLabel(DateTime? finish, {DateTime? now}) {
  final left = sprintDaysLeft(finish, now: now);
  if (left == null) return 'Ended';
  final ago = -left;
  if (ago <= 0) return 'Ends today';
  if (ago == 1) return 'Ended 1 day ago';
  return 'Ended $ago days ago';
}

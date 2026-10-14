import 'package:intl/intl.dart';

/// Turkish, 24h, Monday-first date helpers. All inputs are converted to local time.
class Dates {
  static final day = DateFormat('d MMMM yyyy, EEEE', 'tr');
  static final dayShort = DateFormat('d MMM EEE', 'tr');
  static final monthYear = DateFormat('MMMM yyyy', 'tr');
  static final time = DateFormat('HH:mm', 'tr');
  static final dateTime = DateFormat('EEE d MMM HH:mm', 'tr');
  static final weekdayShort = DateFormat('EEE', 'tr');
  static final dayMonthShort = DateFormat('d MMM', 'tr');

  static DateTime startOfDay(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static DateTime startOfMonth(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month);
  }

  static DateTime addMonths(DateTime d, int n) => DateTime(d.year, d.month + n, 1);

  static bool sameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// Monday = 0 … Sunday = 6
  static int weekdayIndex(DateTime d) => (d.weekday + 6) % 7;

  /// Grid start (Monday) for a 6-row month view.
  static DateTime gridStart(DateTime month) {
    final first = startOfMonth(month);
    return first.subtract(Duration(days: weekdayIndex(first)));
  }

  static String relativeDayLabel(DateTime d, String today) {
    final now = DateTime.now();
    if (sameDay(d, now)) return today;
    return day.format(d.toLocal());
  }
}

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// IANA timezone support. Call [Tz.init] once at startup.
class Tz {
  Tz._();

  static String _local = 'Europe/Istanbul';
  static bool _ready = false;

  static Future<void> init() async {
    if (!_ready) {
      tzdata.initializeTimeZones();
      _ready = true;
    }
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (isValid(info.identifier)) _local = info.identifier;
    } catch (_) {
      // keep the default
    }
  }

  /// For tests: initialize the database without a platform channel.
  static void initForTest([String local = 'Europe/Istanbul']) {
    if (!_ready) {
      tzdata.initializeTimeZones();
      _ready = true;
    }
    _local = local;
  }

  static String get local => _local;

  static bool isValid(String name) {
    try {
      tz.getLocation(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  static tz.Location location(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.UTC;
    }
  }

  /// The wall-clock time of [utc] in [zone], returned as a UTC-flagged
  /// DateTime whose fields equal the local fields ("floating" time).
  static DateTime toWall(DateTime utc, String zone) {
    final t = tz.TZDateTime.from(utc.toUtc(), location(zone));
    return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond, t.microsecond);
  }

  /// Inverse of [toWall]: interpret the fields of [wall] as local time in [zone].
  static DateTime fromWall(DateTime wall, String zone) {
    return tz.TZDateTime(location(zone), wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second,
            wall.millisecond, wall.microsecond)
        .toUtc();
  }
}

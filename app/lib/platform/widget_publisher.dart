import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../core/dates.dart';
import '../core/recurrence.dart';
import '../data/repositories/repositories.dart';

/// Keeps the Android home-screen widget's "today" list current.
class WidgetPublisher {
  WidgetPublisher(this.events, this.calendars);
  final EventRepository events;
  final CalendarRepository calendars;
  StreamSubscription<List<Occurrence>>? _sub;
  Timer? _midnight;

  static const androidProvider = 'AgendaWidgetProvider';

  void start() {
    if (!Platform.isAndroid) return;
    _listen();
    _scheduleMidnight();
  }

  void _listen() {
    _sub?.cancel();
    final from = Dates.startOfDay(DateTime.now());
    final to = from.add(const Duration(days: 1));
    _sub = events.watchOccurrences(from, to).listen((occ) async {
      final cals = {for (final c in await calendars.watchAll().first) c.id: c};
      final visible = occ.where((o) => cals[o.calendarId]?.visible ?? true).toList();
      await publish(visible);
    });
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      _listen();
      _scheduleMidnight();
    });
  }

  Future<void> publish(List<Occurrence> today) async {
    final lines = today.take(8).map((o) {
      final time = o.allDay ? '•' : Dates.time.format(o.start.toLocal());
      return {'time': time, 'title': o.title};
    }).toList();
    try {
      await HomeWidget.saveWidgetData<String>('today_date', Dates.dayShort.format(DateTime.now()));
      await HomeWidget.saveWidgetData<String>('today_lines', jsonEncode(lines));
      await HomeWidget.updateWidget(androidName: androidProvider);
    } catch (_) {
      // widget host missing (tests, emulator without launcher)
    }
  }

  void stop() {
    _sub?.cancel();
    _midnight?.cancel();
  }
}

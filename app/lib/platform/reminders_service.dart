import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/dates.dart';
import '../core/recurrence.dart';
import '../core/tz.dart';
import '../data/repositories/repositories.dart';
import '../data/sync/mappers.dart';
import 'app_intents.dart';

/// Schedules local reminder notifications for upcoming occurrences and keeps
/// them in sync with the database (works fully offline).
///
/// Strategy: a window of [horizon] days is expanded, every (occurrence, reminder)
/// pair gets a stable id, and on every change the whole window is re-planned:
/// pending ids that are no longer wanted are cancelled, new ones scheduled.
class RemindersService {
  RemindersService(this.events, this.calendars, {FlutterLocalNotificationsPlugin? plugin, this.horizon = const Duration(days: 14)})
      : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final EventRepository events;
  final CalendarRepository calendars;
  final FlutterLocalNotificationsPlugin plugin;
  final Duration horizon;

  static const channelId = 'reminders';
  static const maxPending = 400; // Android caps alarms around 500 per app

  StreamSubscription<List<Occurrence>>? _sub;
  Timer? _debounce;
  Timer? _rollover;
  bool _initialized = false;
  bool _exactAllowed = false;

  bool get supported => Platform.isAndroid || Platform.isMacOS;
  bool get exactAllowed => _exactAllowed;

  Future<void> init() async {
    if (!supported || _initialized) return;
    _initialized = true;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_capture'),
        macOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) AppIntents.instance.emit(AppIntent(AppIntentType.openEvent, text: id));
      },
    );
    if (Platform.isAndroid) {
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      _exactAllowed = await android?.canScheduleExactNotifications() ?? false;
    } else {
      _exactAllowed = true;
    }
  }

  /// Asks for the OS permissions reminders need. Returns true when notifications may be shown.
  Future<bool> requestPermissions({bool exact = true}) async {
    if (!supported) return false;
    await init();
    if (Platform.isAndroid) {
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      if (exact) {
        _exactAllowed = (await android?.canScheduleExactNotifications() ?? false) || (await android?.requestExactAlarmsPermission() ?? false);
      }
      return granted;
    }
    final mac = plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    return await mac?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
  }

  /// Starts watching the database; re-plans after every change (debounced).
  void start() {
    if (!supported) return;
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    final from = DateTime.now();
    _sub = events.watchOccurrences(from, from.add(horizon)).listen((occ) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 1), () => replan(occ));
    });
    // re-expand the window every 6 hours so it keeps sliding forward
    _rollover?.cancel();
    _rollover = Timer(const Duration(hours: 6), _listen);
  }

  /// Called after a sync applied remote changes.
  Future<void> refresh() async {
    final from = DateTime.now();
    replan(await events.watchOccurrences(from, from.add(horizon)).first);
  }

  /// (occurrence, minutes) → stable 31-bit notification id.
  static int reminderId(String eventId, DateTime occurrenceStart, int minutes) {
    var h = 17;
    for (final c in '$eventId|${occurrenceStart.toUtc().millisecondsSinceEpoch}|$minutes'.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h == 0 ? 1 : h;
  }

  /// Computes the wanted (id → plan) map for the given occurrences.
  Future<Map<int, ReminderPlan>> plan(List<Occurrence> occ, {DateTime? now}) async {
    now ??= DateTime.now();
    final cals = {for (final c in await calendars.watchAll().first) c.id: c};
    final wanted = <int, ReminderPlan>{};
    for (final o in occ) {
      final cal = cals[o.calendarId];
      if (cal == null || cal.source == 'ics' || o.event.deletedAt != null) continue;
      for (final m in eventReminders(o.event)) {
        final at = o.start.subtract(Duration(minutes: m));
        if (!at.isAfter(now)) continue;
        final id = reminderId(o.event.id, o.start, m);
        wanted[id] = ReminderPlan(id: id, at: at, minutesBefore: m, occurrence: o);
      }
    }
    final sorted = wanted.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    return {for (final p in sorted.take(maxPending)) p.id: p};
  }

  Future<void> replan(List<Occurrence> occ) async {
    if (!supported) return;
    await init();
    final wanted = await plan(occ);
    final pending = await plugin.pendingNotificationRequests();
    final pendingIds = pending.map((p) => p.id).toSet();
    for (final p in pending) {
      if (!wanted.containsKey(p.id)) await plugin.cancel(id: p.id);
    }
    for (final p in wanted.values) {
      if (pendingIds.contains(p.id)) continue; // already scheduled with identical id → identical content
      await _schedule(p);
    }
  }

  Future<void> _schedule(ReminderPlan p) async {
    final o = p.occurrence;
    final time = o.allDay ? Dates.dayShort.format(o.start.toLocal()) : Dates.time.format(o.start.toLocal());
    final body = p.minutesBefore == 0 ? '$time · şimdi' : '$time · ${_relative(p.minutesBefore)}';
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Hatırlatıcılar',
        channelDescription: 'Etkinlik hatırlatıcıları',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      macOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    final tzAt = tz.TZDateTime.from(p.at.toUtc(), Tz.location(Tz.local));
    try {
      await plugin.zonedSchedule(
        id: p.id,
        title: o.title,
        body: [body, if (o.event.location.isNotEmpty) o.event.location].join(' · '),
        scheduledDate: tzAt,
        notificationDetails: details,
        androidScheduleMode: _exactAllowed ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: o.event.id,
      );
    } catch (_) {
      // permission revoked meanwhile; the settings screen explains how to fix it
    }
  }

  static String _relative(int minutes) {
    if (minutes % 1440 == 0) return '${minutes ~/ 1440} gün sonra';
    if (minutes % 60 == 0) return '${minutes ~/ 60} saat sonra';
    return '$minutes dk sonra';
  }

  Future<void> cancelAll() async {
    if (!supported) return;
    await init();
    await plugin.cancelAll();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _debounce?.cancel();
    _rollover?.cancel();
  }
}

class ReminderPlan {
  ReminderPlan({required this.id, required this.at, required this.minutesBefore, required this.occurrence});
  final int id;
  final DateTime at;
  final int minutesBefore;
  final Occurrence occurrence;
}


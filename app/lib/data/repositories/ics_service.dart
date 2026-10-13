import 'package:dio/dio.dart';

import '../db/database.dart';
import 'repositories.dart';

/// Fetches ICS subscription feeds and stores their events locally.
class IcsService {
  IcsService(this.calendars, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(receiveTimeout: const Duration(seconds: 30)));

  final CalendarRepository calendars;
  final Dio _dio;

  /// Default suggestion shown in the subscribe dialog (Google's public Turkish holiday feed).
  static const turkishHolidaysUrl =
      'https://calendar.google.com/calendar/ical/tr.turkish%23holiday%40group.v.calendar.google.com/public/basic.ics';

  Future<int> refresh(Calendar sub) async {
    final url = sub.icsUrl;
    if (url == null) return 0;
    final res = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain));
    return calendars.applyFeed(sub, res.data ?? '');
  }

  /// Refreshes every subscription older than [maxAge]; errors are swallowed per feed.
  Future<void> refreshStale({Duration maxAge = const Duration(hours: 12)}) async {
    final all = await calendars.watchAll().first;
    final now = DateTime.now().toUtc();
    for (final c in all.where((c) => c.source == 'ics')) {
      if (c.lastFetchedAt != null && now.difference(c.lastFetchedAt!) < maxAge) continue;
      try {
        await refresh(c);
      } catch (_) {
        // offline or bad feed: keep the previous events
      }
    }
  }
}

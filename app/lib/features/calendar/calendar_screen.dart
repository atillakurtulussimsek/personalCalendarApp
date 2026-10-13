import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'event_sheet.dart';

enum CalendarMode { month, agenda }

/// Month grid + selected-day list, or an agenda of upcoming events.
/// Recurring events are shown only on their first occurrence until phase 3.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarMode _mode = CalendarMode.month;
  DateTime _month = Dates.startOfMonth(DateTime.now());
  DateTime _selected = Dates.startOfDay(DateTime.now());

  Future<void> createEvent() => showEventSheet(context, ref, initialDay: _selected);

  void _goToday() => setState(() {
        _month = Dates.startOfMonth(DateTime.now());
        _selected = Dates.startOfDay(DateTime.now());
      });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final from = Dates.gridStart(_month);
    final to = from.add(const Duration(days: 42));
    final agendaFrom = Dates.startOfDay(DateTime.now());
    final agendaTo = agendaFrom.add(const Duration(days: 60));
    final range = _mode == CalendarMode.month ? (from, to) : (agendaFrom, agendaTo);
    final eventsAsync = ref.watch(_rangeProvider(range));
    final calendars = {for (final c in ref.watch(calendarsProvider).value ?? const <Calendar>[]) c.id: c};
    final events = (eventsAsync.value ?? const <Event>[]).where((e) => calendars[e.calendarId]?.visible ?? true).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _shiftSelected(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _shiftSelected(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _shiftSelected(-7),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _shiftSelected(7),
        const SingleActivator(LogicalKeyboardKey.keyT): _goToday,
      },
      child: Focus(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  SegmentedButton<CalendarMode>(
                    segments: [
                      ButtonSegment(value: CalendarMode.month, label: Text(l.month)),
                      ButtonSegment(value: CalendarMode.agenda, label: Text(l.agenda)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                    showSelectedIcon: false,
                  ),
                  const Spacer(),
                  if (_mode == CalendarMode.month) ...[
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftMonth(-1)),
                    Text(Dates.monthYear.format(_month), style: Theme.of(context).textTheme.titleMedium),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shiftMonth(1)),
                  ],
                  TextButton(onPressed: _goToday, child: Text(l.today)),
                ],
              ),
            ),
            Expanded(
              child: _mode == CalendarMode.month
                  ? _MonthView(
                      month: _month,
                      selected: _selected,
                      events: events,
                      calendars: calendars,
                      onSelect: (d) => setState(() => _selected = d),
                      onOpen: (e) => showEventSheet(context, ref, event: e),
                    )
                  : _AgendaView(events: events, calendars: calendars, onOpen: (e) => showEventSheet(context, ref, event: e)),
            ),
          ],
        ),
      ),
    );
  }

  void _shiftMonth(int n) => setState(() => _month = Dates.addMonths(_month, n));

  void _shiftSelected(int days) => setState(() {
        _selected = _selected.add(Duration(days: days));
        _month = Dates.startOfMonth(_selected);
      });
}

final _rangeProvider = StreamProvider.autoDispose.family<List<Event>, (DateTime, DateTime)>(
  (ref, r) => ref.watch(eventRepositoryProvider).watchRange(r.$1, r.$2),
);

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.selected,
    required this.events,
    required this.calendars,
    required this.onSelect,
    required this.onOpen,
  });

  final DateTime month;
  final DateTime selected;
  final List<Event> events;
  final Map<String, Calendar> calendars;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<Event> onOpen;

  List<Event> _eventsOn(DateTime day) {
    final start = day;
    final end = day.add(const Duration(days: 1));
    return events.where((e) {
      final s = e.startAt.toLocal();
      final en = e.endAt.toLocal();
      return s.isBefore(end) && (en.isAfter(start) || Dates.sameDay(s, day));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final gridStart = Dates.gridStart(month);
    const weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final selectedEvents = _eventsOn(selected);

    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Center(child: Text(w, style: Theme.of(context).textTheme.labelSmall)),
              ),
          ],
        ),
        AspectRatio(
          aspectRatio: 7 / 5.2,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
            itemCount: 42,
            itemBuilder: (context, i) {
              final day = gridStart.add(Duration(days: i));
              final inMonth = day.month == month.month;
              final isSelected = Dates.sameDay(day, selected);
              final isToday = Dates.sameDay(day, DateTime.now());
              final dayEvents = _eventsOn(day);
              return InkWell(
                onTap: () => onSelect(day),
                onDoubleTap: () => onSelect(day),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected ? scheme.primaryContainer : null,
                    border: isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${day.day}',
                          style: TextStyle(
                            color: inMonth ? scheme.onSurface : scheme.outline,
                            fontWeight: isToday ? FontWeight.bold : null,
                          )),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: [
                          for (final e in dayEvents.take(4))
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colorFromHex(calendars[e.calendarId]?.color ?? '#3B82F6'),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(Dates.relativeDayLabel(selected, l.today), style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        Expanded(
          child: selectedEvents.isEmpty
              ? Center(child: Text(l.noEvents, style: TextStyle(color: scheme.outline)))
              : ListView(
                  children: [for (final e in selectedEvents) EventTile(event: e, calendar: calendars[e.calendarId], onTap: () => onOpen(e))],
                ),
        ),
      ],
    );
  }
}

class _AgendaView extends StatelessWidget {
  const _AgendaView({required this.events, required this.calendars, required this.onOpen});
  final List<Event> events;
  final Map<String, Calendar> calendars;
  final ValueChanged<Event> onOpen;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (events.isEmpty) {
      return Center(child: Text(l.noEvents, style: TextStyle(color: Theme.of(context).colorScheme.outline)));
    }
    final groups = <DateTime, List<Event>>{};
    for (final e in events) {
      groups.putIfAbsent(Dates.startOfDay(e.startAt), () => []).add(e);
    }
    final days = groups.keys.toList()..sort();
    return ListView.builder(
      itemCount: days.length,
      itemBuilder: (context, i) {
        final d = days[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(Dates.relativeDayLabel(d, l.today), style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final e in groups[d]!) EventTile(event: e, calendar: calendars[e.calendarId], onTap: () => onOpen(e)),
          ],
        );
      },
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.calendar, this.onTap});
  final Event event;
  final Calendar? calendar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final time = event.allDay ? l.allDay : '${Dates.time.format(event.startAt.toLocal())}–${Dates.time.format(event.endAt.toLocal())}';
    return ListTile(
      dense: true,
      leading: Container(
        width: 4,
        height: 36,
        decoration: BoxDecoration(color: colorFromHex(calendar?.color ?? '#3B82F6'), borderRadius: BorderRadius.circular(2)),
      ),
      title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([time, if (event.location.isNotEmpty) event.location].join(' · ')),
      trailing: event.rrule != null ? const Icon(Icons.repeat, size: 16) : null,
      onTap: onTap,
    );
  }
}

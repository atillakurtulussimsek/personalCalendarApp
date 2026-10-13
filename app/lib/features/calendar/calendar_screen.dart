import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'calendars_screen.dart';
import 'edit_scope_dialog.dart';
import 'event_editor_screen.dart';
import 'time_grid.dart';

enum CalendarMode { month, week, day, agenda }

/// Month / week / day / agenda views over expanded occurrences.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarMode _mode = CalendarMode.month;
  DateTime _selected = Dates.startOfDay(DateTime.now());

  DateTime get _month => Dates.startOfMonth(_selected);
  DateTime get _weekStart => _selected.subtract(Duration(days: Dates.weekdayIndex(_selected)));

  Future<void> createEvent() => openEventEditor(context, initialStart: _selected.add(Duration(hours: DateTime.now().hour + 1)));

  void _goToday() => setState(() => _selected = Dates.startOfDay(DateTime.now()));

  void goToday() => _goToday();

  (DateTime, DateTime) get _range => switch (_mode) {
        CalendarMode.month => (Dates.gridStart(_month), Dates.gridStart(_month).add(const Duration(days: 42))),
        CalendarMode.week => (_weekStart, _weekStart.add(const Duration(days: 7))),
        CalendarMode.day => (_selected, _selected.add(const Duration(days: 1))),
        CalendarMode.agenda => (Dates.startOfDay(DateTime.now()), Dates.startOfDay(DateTime.now()).add(const Duration(days: 60))),
      };

  void _shift(int n) => setState(() {
        _selected = switch (_mode) {
          CalendarMode.month => Dates.addMonths(_month, n),
          CalendarMode.week => _selected.add(Duration(days: 7 * n)),
          _ => _selected.add(Duration(days: n)),
        };
      });

  Future<void> _move(Occurrence o, Duration delta) async {
    final scope = o.isRecurring ? await showEditScopeDialog(context, allowFollowing: !o.isException) : EditScope.all;
    if (scope == null) return;
    await ref.read(eventRepositoryProvider).moveOccurrence(o, delta: delta, scope: scope);
  }

  Future<void> _resize(Occurrence o, Duration dur) async {
    final scope = o.isRecurring ? await showEditScopeDialog(context, allowFollowing: !o.isException) : EditScope.all;
    if (scope == null) return;
    await ref.read(eventRepositoryProvider).moveOccurrence(o, newDuration: dur, scope: scope);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final range = _range;
    final calendars = {for (final c in ref.watch(calendarsProvider).value ?? const <Calendar>[]) c.id: c};
    final occ = (ref.watch(_occurrencesProvider(range)).value ?? const <Occurrence>[])
        .where((o) => calendars[o.calendarId]?.visible ?? true)
        .toList();

    final title = switch (_mode) {
      CalendarMode.month => Dates.monthYear.format(_month),
      CalendarMode.week => '${Dates.dayShort.format(_weekStart)} – ${Dates.dayShort.format(_weekStart.add(const Duration(days: 6)))}',
      CalendarMode.day => Dates.day.format(_selected),
      CalendarMode.agenda => l.agenda,
    };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _shiftSelected(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _shiftSelected(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _shiftSelected(-7),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _shiftSelected(7),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _shift(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _shift(1),
        const SingleActivator(LogicalKeyboardKey.keyT): _goToday,
        const SingleActivator(LogicalKeyboardKey.keyM): () => setState(() => _mode = CalendarMode.month),
        const SingleActivator(LogicalKeyboardKey.keyW): () => setState(() => _mode = CalendarMode.week),
        const SingleActivator(LogicalKeyboardKey.keyD): () => setState(() => _mode = CalendarMode.day),
        const SingleActivator(LogicalKeyboardKey.keyA): () => setState(() => _mode = CalendarMode.agenda),
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
                      ButtonSegment(value: CalendarMode.week, label: Text(l.week)),
                      ButtonSegment(value: CalendarMode.day, label: Text(l.day)),
                      ButtonSegment(value: CalendarMode.agenda, label: Text(l.agenda)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.calendar_view_month_outlined),
                    tooltip: l.calendars,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CalendarsScreen())),
                  ),
                ],
              ),
            ),
            if (_mode != CalendarMode.agenda)
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                  Expanded(child: Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
                  TextButton(onPressed: _goToday, child: Text(l.today)),
                ],
              ),
            Expanded(
              child: switch (_mode) {
                CalendarMode.month => _MonthView(
                    month: _month,
                    selected: _selected,
                    occurrences: occ,
                    calendars: calendars,
                    onSelect: (d) => setState(() => _selected = d),
                    onOpen: (o) => openEventEditor(context, occurrence: o),
                    onOpenDay: (d) => setState(() {
                      _selected = d;
                      _mode = CalendarMode.day;
                    }),
                  ),
                CalendarMode.week || CalendarMode.day => TimeGrid(
                    key: ValueKey('${_mode}_${range.$1}'),
                    firstDay: range.$1,
                    days: _mode == CalendarMode.week ? 7 : 1,
                    occurrences: occ,
                    calendars: calendars,
                    onOpen: (o) => openEventEditor(context, occurrence: o),
                    onCreate: (start, allDay) => openEventEditor(context, initialStart: start, allDay: allDay),
                    onMove: _move,
                    onResize: _resize,
                  ),
                CalendarMode.agenda => _AgendaView(occurrences: occ, calendars: calendars, onOpen: (o) => openEventEditor(context, occurrence: o)),
              },
            ),
          ],
        ),
      ),
    );
  }

  void _shiftSelected(int days) => setState(() => _selected = _selected.add(Duration(days: days)));
}

final _occurrencesProvider = StreamProvider.autoDispose.family<List<Occurrence>, (DateTime, DateTime)>(
  (ref, r) => ref.watch(eventRepositoryProvider).watchOccurrences(r.$1, r.$2),
);

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.selected,
    required this.occurrences,
    required this.calendars,
    required this.onSelect,
    required this.onOpen,
    required this.onOpenDay,
  });

  final DateTime month;
  final DateTime selected;
  final List<Occurrence> occurrences;
  final Map<String, Calendar> calendars;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<Occurrence> onOpen;
  final ValueChanged<DateTime> onOpenDay;

  List<Occurrence> _on(DateTime day) {
    final end = day.add(const Duration(days: 1));
    return occurrences.where((o) => o.start.toLocal().isBefore(end) && o.end.toLocal().isAfter(day)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final gridStart = Dates.gridStart(month);
    const weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final selectedItems = _on(selected);

    return Column(
      children: [
        Row(children: [for (final w in weekdays) Expanded(child: Center(child: Text(w, style: Theme.of(context).textTheme.labelSmall)))]),
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
              final items = _on(day);
              return InkWell(
                onTap: () => onSelect(day),
                onDoubleTap: () => onOpenDay(day),
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
                          style: TextStyle(color: inMonth ? scheme.onSurface : scheme.outline, fontWeight: isToday ? FontWeight.bold : null)),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: [
                          for (final o in items.take(4))
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: colorFromHex(calendars[o.calendarId]?.color ?? '#3B82F6')),
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
          child: selectedItems.isEmpty
              ? Center(child: Text(l.noEvents, style: TextStyle(color: scheme.outline)))
              : ListView(children: [for (final o in selectedItems) OccurrenceTile(occurrence: o, calendar: calendars[o.calendarId], onTap: () => onOpen(o))]),
        ),
      ],
    );
  }
}

class _AgendaView extends StatelessWidget {
  const _AgendaView({required this.occurrences, required this.calendars, required this.onOpen});
  final List<Occurrence> occurrences;
  final Map<String, Calendar> calendars;
  final ValueChanged<Occurrence> onOpen;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (occurrences.isEmpty) {
      return Center(child: Text(l.noEvents, style: TextStyle(color: Theme.of(context).colorScheme.outline)));
    }
    final groups = <DateTime, List<Occurrence>>{};
    for (final o in occurrences) {
      groups.putIfAbsent(Dates.startOfDay(o.start), () => []).add(o);
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
            for (final o in groups[d]!) OccurrenceTile(occurrence: o, calendar: calendars[o.calendarId], onTap: () => onOpen(o)),
          ],
        );
      },
    );
  }
}

class OccurrenceTile extends StatelessWidget {
  const OccurrenceTile({super.key, required this.occurrence, this.calendar, this.onTap});
  final Occurrence occurrence;
  final Calendar? calendar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final o = occurrence;
    final time = o.allDay ? l.allDay : '${Dates.time.format(o.start.toLocal())}–${Dates.time.format(o.end.toLocal())}';
    return ListTile(
      dense: true,
      leading: Container(
        width: 4,
        height: 36,
        decoration: BoxDecoration(color: colorFromHex(calendar?.color ?? '#3B82F6'), borderRadius: BorderRadius.circular(2)),
      ),
      title: Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([time, if (o.event.location.isNotEmpty) o.event.location].join(' · ')),
      trailing: o.isRecurring ? const Icon(Icons.repeat, size: 16) : null,
      onTap: onTap,
    );
  }
}

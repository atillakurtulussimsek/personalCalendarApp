import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/db/database.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../home/shell_actions.dart';
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

  /// Day used as context for quick capture ("15:00 toplantı" lands here).
  DateTime get selectedDay => _selected;

  DateTime get _month => Dates.startOfMonth(_selected);

  /// Phones show a rolling 5-day window starting at the selected day;
  /// wide screens show the Monday-based week.
  bool get _wide => MediaQuery.sizeOf(context).width >= 700;
  int get _weekDays => _wide ? 7 : 5;
  DateTime get _weekStart => _wide ? _selected.subtract(Duration(days: Dates.weekdayIndex(_selected))) : _selected;

  Future<void> createEvent() => openEventEditor(context, initialStart: _selected.add(Duration(hours: DateTime.now().hour + 1)));

  void goToday() => setState(() => _selected = Dates.startOfDay(DateTime.now()));

  (DateTime, DateTime) get _range => switch (_mode) {
        CalendarMode.month => (Dates.gridStart(_month), Dates.gridStart(_month).add(const Duration(days: 42))),
        CalendarMode.week => (_weekStart, _weekStart.add(Duration(days: _weekDays))),
        CalendarMode.day => (_selected, _selected.add(const Duration(days: 1))),
        CalendarMode.agenda => (Dates.startOfDay(DateTime.now()), Dates.startOfDay(DateTime.now()).add(const Duration(days: 60))),
      };

  void _shift(int n) => setState(() {
        _selected = switch (_mode) {
          CalendarMode.month => Dates.addMonths(_month, n),
          CalendarMode.week => _selected.add(Duration(days: _weekDays * n)),
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
    final t = context.tokens;
    final range = _range;
    final calendars = {for (final c in ref.watch(calendarsProvider).value ?? const <Calendar>[]) c.id: c};
    final occ = (ref.watch(_occurrencesProvider(range)).value ?? const <Occurrence>[])
        .where((o) => calendars[o.calendarId]?.visible ?? true)
        .toList();

    final (String title, String? suffix) = switch (_mode) {
      CalendarMode.month => (DateFormat('MMMM', 'tr').format(_month), '${_month.year}'),
      CalendarMode.week => (_rangeTitle(range.$1, range.$2.subtract(const Duration(days: 1))), null),
      CalendarMode.day => (DateFormat('d MMMM', 'tr').format(_selected), DateFormat('EEEE', 'tr').format(_selected)),
      CalendarMode.agenda => (l.agenda, null),
    };

    Widget navButton(IconData icon, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: t.fill,
            borderRadius: BorderRadius.circular(Radii.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.lg),
              onTap: onTap,
              child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 18, color: t.body)),
            ),
          ),
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _shiftSelected(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _shiftSelected(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _shiftSelected(-7),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _shiftSelected(7),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _shift(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _shift(1),
        const SingleActivator(LogicalKeyboardKey.keyT): goToday,
        const SingleActivator(LogicalKeyboardKey.keyM): () => setState(() => _mode = CalendarMode.month),
        const SingleActivator(LogicalKeyboardKey.keyW): () => setState(() => _mode = CalendarMode.week),
        const SingleActivator(LogicalKeyboardKey.keyD): () => setState(() => _mode = CalendarMode.day),
        const SingleActivator(LogicalKeyboardKey.keyA): () => setState(() => _mode = CalendarMode.agenda),
      },
      child: Focus(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: title,
              titleSuffix: suffix,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_mode != CalendarMode.agenda) ...[
                  navButton(Icons.chevron_left_rounded, () => _shift(-1)),
                  Pill(label: l.today, onTap: goToday),
                  navButton(Icons.chevron_right_rounded, () => _shift(1)),
                ],
                const ShellActions(compact: true),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
              child: SegmentedButton<CalendarMode>(
                segments: [
                  ButtonSegment(value: CalendarMode.month, label: Text(l.month)),
                  ButtonSegment(value: CalendarMode.week, label: Text(l.week)),
                  ButtonSegment(value: CalendarMode.day, label: Text(l.day)),
                  ButtonSegment(value: CalendarMode.agenda, label: Text(l.agenda)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
                showSelectedIcon: false,
              ),
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
                    key: ValueKey('${_mode}_${range.$1}_$_weekDays'),
                    firstDay: range.$1,
                    days: _mode == CalendarMode.week ? _weekDays : 1,
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

  static String _rangeTitle(DateTime a, DateTime b) {
    if (a.month == b.month) return '${a.day} – ${b.day} ${DateFormat('MMMM', 'tr').format(a)}';
    return '${DateFormat('d MMM', 'tr').format(a)} – ${DateFormat('d MMM', 'tr').format(b)}';
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

  bool _holiday(List<Occurrence> items) => items.any((o) => calendars[o.calendarId]?.source == 'ics');

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final gridStart = Dates.gridStart(month);
    const weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final selectedItems = _on(selected);
    final wide = MediaQuery.sizeOf(context).width >= 700;

    Widget cell(DateTime day) {
      final inMonth = day.month == month.month;
      final isSelected = Dates.sameDay(day, selected);
      final isToday = Dates.sameDay(day, DateTime.now());
      final items = _on(day);
      final holiday = _holiday(items);
      final fg = isSelected
          ? Theme.of(context).colorScheme.onPrimary
          : !inMonth
              ? t.ink.withValues(alpha: .25)
              : holiday
                  ? t.danger
                  : isToday
                      ? t.accent
                      : t.ink;
      return GestureDetector(
        onTap: () => onSelect(day),
        onDoubleTap: () => onOpenDay(day),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? t.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: isSelected ? [BoxShadow(color: t.accent.withValues(alpha: .32), blurRadius: 16, offset: const Offset(0, 6))] : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: Space.xs),
          child: Column(
            mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center,
            crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Text('${day.day}',
                  style: context.text.bodyLarge?.copyWith(
                    color: fg,
                    fontWeight: isToday || isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: tabularFigures,
                  )),
              const SizedBox(height: Space.xs),
              if (wide)
                // wide screens: titles instead of dots
                for (final o in items.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(o.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          fontSize: 12,
                          color: isSelected ? Colors.white : colorFromHex(calendars[o.calendarId]?.color ?? '#4F5BD5'),
                        )),
                  )
              else
                SizedBox(
                  height: 4,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final o in items.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Dot(isSelected ? Colors.white : colorFromHex(calendars[o.calendarId]?.color ?? '#4F5BD5'), size: 4),
                      ),
                  ]),
                ),
            ],
          ),
        ),
      );
    }

    final grid = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Column(children: [
        Row(children: [
          for (final w in weekdays)
            Expanded(child: SizedBox(height: Space.xl, child: Center(child: Text(w, style: context.text.labelSmall?.copyWith(fontSize: 12))))),
        ]),
        for (var r = 0; r < 6; r++)
          SizedBox(
            height: wide ? 88 : 48,
            child: Row(children: [for (var c = 0; c < 7; c++) Expanded(child: cell(gridStart.add(Duration(days: r * 7 + c))))]),
          ),
      ]),
    );

    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
        child: SectionHeader(Dates.relativeDayLabel(selected, l.today), trailing: '${selectedItems.length}'),
      ),
      if (selectedItems.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Text(l.noEvents, style: context.text.bodySmall),
        )
      else
        for (final o in selectedItems)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: OccurrenceTile(occurrence: o, calendar: calendars[o.calendarId], onTap: () => onOpen(o)),
          ),
    ]);

    return ListView(padding: const EdgeInsets.only(bottom: Space.lg), children: [
      grid,
      const SizedBox(height: Space.lg),
      const Divider(indent: Space.lg, endIndent: Space.lg),
      list,
    ]);
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
      return EmptyState(icon: Icons.event_available_outlined, title: l.freeDayTitle, message: l.freeDayBody);
    }
    final groups = <DateTime, List<Occurrence>>{};
    for (final o in occurrences) {
      groups.putIfAbsent(Dates.startOfDay(o.start), () => []).add(o);
    }
    final days = groups.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final d = days[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(Dates.relativeDayLabel(d, l.today), small: true),
            for (final o in groups[d]!)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: OccurrenceTile(occurrence: o, calendar: calendars[o.calendarId], onTap: () => onOpen(o)),
              ),
          ]),
        );
      },
    );
  }
}

/// Event row: colour bar, time range, title, recurrence marker.
class OccurrenceTile extends StatelessWidget {
  const OccurrenceTile({super.key, required this.occurrence, this.calendar, this.onTap});
  final Occurrence occurrence;
  final Calendar? calendar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final o = occurrence;
    final now = DateTime.now();
    final current = !o.allDay && o.start.isBefore(now) && o.end.isAfter(now);
    final time = o.allDay ? l.allDay : '${Dates.time.format(o.start.toLocal())} – ${Dates.time.format(o.end.toLocal())}';
    return AppCard.tight(
      onTap: onTap,
      child: Row(children: [
        ColorBar(colorFromHex(calendar?.color ?? '#4F5BD5'), height: o.event.location.isEmpty ? 24 : 40),
        const SizedBox(width: Space.md),
        SizedBox(width: 104, child: Text(time, style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures))),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: current ? context.text.titleSmall : context.text.bodyLarge?.copyWith(color: t.ink)),
            if (o.event.location.isNotEmpty) Text(o.event.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
          ]),
        ),
        if (o.isRecurring) Icon(Icons.repeat_rounded, size: 16, color: t.faint),
      ]),
    );
  }
}

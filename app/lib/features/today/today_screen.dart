import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/db/database.dart';
import '../../data/sync/mappers.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../calendar/event_editor_screen.dart';
import '../home/shell_actions.dart';
import '../notes/note_editor_screen.dart';

/// Ticks every 30 s so countdowns and the "now" line stay current.
final clockProvider = StreamProvider<DateTime>((ref) => Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()));

/// Occurrences from the start of [day] for two days (today + tomorrow).
final _twoDaysProvider = StreamProvider.autoDispose.family<List<Occurrence>, DateTime>(
  (ref, day) => ref.watch(eventRepositoryProvider).watchOccurrences(day, day.add(const Duration(days: 2))),
);

/// The landing screen: what is next, today's timeline, today's tasks.
/// In the evening it closes the day and looks at tomorrow (peak-end).
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = Dates.startOfDay(now);
    final tomorrow = today.add(const Duration(days: 1));
    final calendars = {for (final c in ref.watch(calendarsProvider).value ?? const <Calendar>[]) c.id: c};
    bool visible(Occurrence o) => calendars[o.calendarId]?.visible ?? true;
    final all = (ref.watch(_twoDaysProvider(today)).value ?? const <Occurrence>[]).where(visible).toList();
    final todays = all.where((o) => o.start.toLocal().isBefore(tomorrow) && o.end.toLocal().isAfter(today)).toList();
    final tomorrows = all.where((o) => !o.start.toLocal().isBefore(tomorrow)).toList();
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final todayTasks = tasks
        .where((t) => t.dueAt != null && (t.dueAt!.toLocal().isBefore(tomorrow)) && (!t.done || Dates.sameDay(t.updatedAt, now)))
        .toList()
      ..sort((a, b) => (a.done ? 1 : 0).compareTo(b.done ? 1 : 0));
    final doneCount = todayTasks.where((t) => t.done).length;
    final evening = now.hour >= 18;
    final next = todays.where((o) => !o.allDay && o.end.toLocal().isAfter(now)).firstOrNull;

    final email = ref.watch(userEmailProvider).value ?? '';
    final name = _firstName(email);
    final greeting = switch (now.hour) {
      < 5 => l.greetingNight,
      < 12 => l.greetingMorning,
      < 18 => l.greetingDay,
      _ => l.greetingEvening,
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xl),
      children: [
        PageHeader(
          overline: Dates.day.format(now),
          title: name.isEmpty ? greeting : l.greetingWithName(greeting, name),
          trailing: const ShellActions(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (next != null && !(evening && next.start.toLocal().isAfter(now.add(const Duration(hours: 3)))))
              _NextCard(occurrence: next, now: now, calendars: calendars)
            else if (evening)
              _EveningCard(
                first: tomorrows.where((o) => !o.allDay).firstOrNull ?? tomorrows.firstOrNull,
                summary: l.daySummary(todays.length, doneCount, todayTasks.length),
              ),
            const SizedBox(height: Space.xl),
            if (evening && next == null) ...[
              SectionHeader(l.tomorrow, trailing: l.eventsCount(tomorrows.length)),
              if (tomorrows.isEmpty) _FreeDay() else for (final o in tomorrows) _EventRow(o, calendars),
            ] else ...[
              SectionHeader(l.today, trailing: l.eventsCount(todays.length)),
              if (todays.isEmpty) _FreeDay() else _Timeline(occurrences: todays, now: now, calendars: calendars, highlight: next),
            ],
            if (todayTasks.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              SectionHeader(l.tabTasks, trailing: '$doneCount / ${todayTasks.length}'),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
                radius: Radii.lg,
                child: Column(children: [
                  for (final t in todayTasks) _TaskRow(t, now),
                ]),
              ),
            ],
          ]),
        ),
      ],
    );
  }

  static String _firstName(String email) {
    final local = email.split('@').first.split(RegExp(r'[._\-+]')).first;
    if (local.isEmpty) return '';
    return local[0].toUpperCase() + local.substring(1);
  }
}

String _countdown(L10n l, DateTime start, DateTime end, DateTime now) {
  if (!start.isAfter(now)) return '${l.happeningNow} · ${l.endsInMinutes(end.difference(now).inMinutes.clamp(0, 9999))}';
  final m = start.difference(now).inMinutes + 1;
  if (m < 60) return l.inMinutes(m);
  if (m % 60 == 0 || m >= 300) return l.inHours((m / 60).round());
  return l.inHoursMinutes(m ~/ 60, m % 60);
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.occurrence, required this.now, required this.calendars});
  final Occurrence occurrence;
  final DateTime now;
  final Map<String, Calendar> calendars;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final o = occurrence;
    final reminders = eventReminders(o.event);
    return _GlowCard(
      onTap: () => openEventEditor(context, occurrence: o),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(text: '${l.nextUp} · ', children: [
          TextSpan(text: _countdown(l, o.start.toLocal(), o.end.toLocal(), now), style: TextStyle(color: t.accent, fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(height: Space.sm),
        Text(o.title, style: context.text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.md),
        Wrap(spacing: Space.lg, runSpacing: Space.sm, children: [
          _Meta(Icons.schedule_rounded, '${Dates.time.format(o.start.toLocal())} – ${Dates.time.format(o.end.toLocal())}'),
          if (o.event.location.isNotEmpty) _Meta(Icons.place_outlined, o.event.location),
        ]),
        const SizedBox(height: Space.lg),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          Pill(
            icon: Icons.sticky_note_2_outlined,
            label: l.addNote,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(eventId: o.seriesId))),
          ),
          if (reminders.isNotEmpty) Pill(neutral: true, icon: Icons.notifications_none_rounded, label: l.minutesBefore(reminders.first)),
        ]),
      ]),
    );
  }
}

class _EveningCard extends StatelessWidget {
  const _EveningCard({required this.first, required this.summary});
  final Occurrence? first;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    return _GlowCard(
      onTap: first == null ? null : () => openEventEditor(context, occurrence: first),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (first != null) ...[
          Text.rich(TextSpan(text: '${l.tomorrowFirst} · ', children: [
            TextSpan(
              text: first!.allDay ? l.allDay : Dates.time.format(first!.start.toLocal()),
              style: TextStyle(color: t.accent, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
            ),
          ])),
          const SizedBox(height: Space.sm),
          Text(first!.title, style: context.text.titleLarge),
          const SizedBox(height: Space.md),
        ],
        Text(summary, style: context.text.bodySmall),
      ]),
    );
  }
}

/// Card with a soft accent glow in the corner (the screen's focal point).
class _GlowCard extends StatelessWidget {
  const _GlowCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = BorderRadius.circular(Radii.xl);
    return Container(
      decoration: BoxDecoration(color: t.surface, borderRadius: r, boxShadow: t.shadow),
      child: ClipRRect(
        borderRadius: r,
        child: Stack(children: [
          Positioned(
            right: -56,
            top: -56,
            child: IgnorePointer(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: t.accent.withValues(alpha: .18))),
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(Space.xl), child: SizedBox(width: double.infinity, child: child))),
          ),
        ]),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: context.tokens.secondary),
        const SizedBox(width: Space.sm),
        Text(text, style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures)),
      ]);
}

/// Vertical timeline with coloured nodes and a red "now" line.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.occurrences, required this.now, required this.calendars, this.highlight});
  final List<Occurrence> occurrences;
  final DateTime now;
  final Map<String, Calendar> calendars;
  final Occurrence? highlight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = <Widget>[];
    var nowPlaced = false;
    for (final o in occurrences) {
      if (!nowPlaced && !o.allDay && o.start.toLocal().isAfter(now)) {
        rows.add(_NowLine(now));
        nowPlaced = true;
      }
      rows.add(_TimelineItem(o, color: colorFromHex(calendars[o.calendarId]?.color ?? '#4F5BD5'), emphasized: identical(o, highlight)));
    }
    if (!nowPlaced) rows.add(_NowLine(now));
    return Stack(children: [
      Positioned(left: 7, top: Space.sm, bottom: Space.sm, child: Container(width: 2, color: t.line)),
      Column(children: [for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: r)]),
    ]);
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine(this.now);
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(left: Space.xl),
      child: Row(children: [
        Text(Dates.time.format(now), style: context.text.labelMedium?.copyWith(color: t.danger, fontFeatures: tabularFigures)),
        const SizedBox(width: Space.sm),
        Expanded(child: Container(height: 2, decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(1)))),
      ]),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem(this.o, {required this.color, this.emphasized = false});
  final Occurrence o;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    return Row(children: [
      Container(
        width: 16,
        alignment: Alignment.center,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: t.bg, width: 3)),
        ),
      ),
      const SizedBox(width: Space.sm),
      Expanded(
        child: AppCard.tight(
          onTap: () => openEventEditor(context, occurrence: o),
          child: Row(children: [
            SizedBox(
              width: 48,
              child: Text(o.allDay ? l.allDay : Dates.time.format(o.start.toLocal()),
                  style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures)),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(o.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: emphasized ? context.text.titleSmall : context.text.bodyLarge),
            ),
            if (o.isRecurring) Icon(Icons.repeat_rounded, size: 16, color: t.faint),
          ]),
        ),
      ),
    ]);
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.o, this.calendars);
  final Occurrence o;
  final Map<String, Calendar> calendars;
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: AppCard.tight(
        onTap: () => openEventEditor(context, occurrence: o),
        child: Row(children: [
          ColorBar(colorFromHex(calendars[o.calendarId]?.color ?? '#4F5BD5'), height: 24),
          const SizedBox(width: Space.md),
          SizedBox(width: 48, child: Text(o.allDay ? l.allDay : Dates.time.format(o.start.toLocal()), style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures))),
          Expanded(child: Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyLarge)),
        ]),
      ),
    );
  }
}

class _FreeDay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AppCard(
      child: Row(children: [
        Icon(Icons.wb_sunny_outlined, color: context.tokens.accent),
        const SizedBox(width: Space.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.freeDayTitle, style: context.text.titleSmall),
            const SizedBox(height: Space.xs),
            Text(l.freeDayBody, style: context.text.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow(this.task, this.now);
  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final overdue = !task.done && task.dueAt!.isBefore(now);
    return Row(children: [
      PopCheck(value: task.done, danger: overdue, onChanged: (v) => ref.read(taskRepositoryProvider).setDone(task.id, v)),
      Expanded(
        child: Text(task.title,
            style: task.done
                ? context.text.bodyLarge?.copyWith(color: t.faint, decoration: TextDecoration.lineThrough)
                : context.text.bodyLarge?.copyWith(color: t.ink)),
      ),
      Padding(
        padding: const EdgeInsets.only(right: Space.md),
        child: Text(Dates.sameDay(task.dueAt!, now) ? Dates.time.format(task.dueAt!.toLocal()) : Dates.dateTime.format(task.dueAt!.toLocal()),
            style: context.text.bodySmall?.copyWith(color: overdue ? t.danger : null, fontFeatures: tabularFigures)),
      ),
    ]);
  }
}

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capture_parser.dart';
import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../core/theme.dart';
import '../../core/tz.dart';
import '../../core/ui.dart';
import '../../data/db/database.dart';
import '../../data/repositories/repositories.dart';
import '../../data/sync/mappers.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../notes/note_editor_screen.dart';
import 'edit_scope_dialog.dart';
import 'recurrence_picker.dart';

/// Opens the editor for a new event on [initialStart] or for an existing [occurrence].
Future<void> openEventEditor(BuildContext context,
    {Occurrence? occurrence, DateTime? initialStart, bool allDay = false, CaptureResult? prefill}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => EventEditorScreen(occurrence: occurrence, initialStart: initialStart, initialAllDay: allDay, prefill: prefill),
    fullscreenDialog: true,
  ));
}

class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.occurrence, this.initialStart, this.initialAllDay = false, this.prefill});
  final Occurrence? occurrence;
  final DateTime? initialStart;
  final bool initialAllDay;

  /// Parsed quick-capture result to prefill a new event with.
  final CaptureResult? prefill;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late DateTime _start; // local
  late DateTime _end; // local
  late bool _allDay;
  String? _calendarId;
  String? _rrule;
  late List<int> _reminders;
  late String _timezone;
  String? _error;
  bool _saving = false;

  Event? get _event => widget.occurrence?.event;
  bool get _isNew => widget.occurrence == null;
  bool get _readOnly => _event != null && _event!.version == 0 && _event!.serverSeq == 0 && _isSubscription;
  bool _isSubscription = false;

  @override
  void initState() {
    super.initState();
    final occ = widget.occurrence;
    final e = occ?.event;
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    if (occ != null) {
      _start = occ.start.toLocal();
      _end = occ.end.toLocal();
      _allDay = e!.allDay;
      _calendarId = e.calendarId;
      _rrule = occ.isException ? null : e.rrule;
      _reminders = eventReminders(e);
      _timezone = e.timezone;
      if (_allDay) _end = _end.subtract(const Duration(days: 1));
    } else {
      final init = widget.initialStart ?? DateTime.now();
      _allDay = widget.initialAllDay;
      if (_allDay) {
        _start = Dates.startOfDay(init);
        _end = _start;
      } else {
        final rounded = DateTime(init.year, init.month, init.day, init.hour, (init.minute ~/ 15) * 15);
        _start = widget.initialStart != null ? rounded : rounded.add(const Duration(hours: 1)).copyWith(minute: 0);
        _end = _start.add(const Duration(hours: 1));
      }
      _calendarId = null;
      _rrule = null;
      _reminders = [10];
      _timezone = Tz.local;
      final pf = widget.prefill;
      if (pf != null && pf.isEvent) {
        _title.text = pf.title;
        _location.text = pf.location;
        _start = pf.start!;
        _end = pf.allDay ? pf.end!.subtract(const Duration(days: 1)) : pf.end!;
        _allDay = pf.allDay;
        _rrule = pf.rrule;
        if (pf.reminders.isNotEmpty) _reminders = List.of(pf.reminders);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isStart) async {
    final base = isStart ? _start : _end;
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    var t = TimeOfDay.fromDateTime(base);
    if (!_allDay) {
      final picked = await showTimePicker(
        context: context,
        initialTime: t,
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
      );
      if (picked == null || !mounted) return;
      t = picked;
    }
    setState(() {
      final v = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (isStart) {
        final dur = _end.difference(_start);
        _start = v;
        _end = v.add(dur);
      } else {
        _end = v;
      }
    });
  }

  Future<void> _save() async {
    final l = L10n.of(context);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = l.titleRequired);
      return;
    }
    var start = _start;
    var end = _end;
    if (_allDay) {
      start = Dates.startOfDay(start);
      end = Dates.startOfDay(end).add(const Duration(days: 1));
    }
    if (end.isBefore(start) || (!_allDay && end.isAtSameMomentAs(start))) {
      setState(() => _error = l.endBeforeStart);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(eventRepositoryProvider);
    final calId = _calendarId ?? (await ref.read(calendarRepositoryProvider).ensureDefault()).id;
    try {
      if (_isNew) {
        await repo.create(
          calendarId: calId,
          title: _title.text,
          description: _description.text,
          location: _location.text.trim(),
          startAt: start,
          endAt: end,
          timezone: _timezone,
          allDay: _allDay,
          rrule: _rrule,
          reminders: _reminders,
        );
      } else {
        final occ = widget.occurrence!;
        Event apply(Event base) => base.copyWith(
              calendarId: calId,
              title: _title.text,
              description: _description.text,
              location: _location.text.trim(),
              startAt: start.toUtc(),
              endAt: end.toUtc(),
              allDay: _allDay,
              reminders: jsonEncode(_reminders),
              rrule: Value(_rrule),
            );
        if (occ.isRecurring) {
          final rruleChanged = _rrule != (occ.isException ? null : occ.event.rrule);
          EditScope? scope = EditScope.all;
          if (!(rruleChanged && !occ.isException)) {
            if (!mounted) return;
            scope = await showEditScopeDialog(context, allowFollowing: !occ.isException);
          }
          if (scope == null) {
            setState(() => _saving = false);
            return;
          }
          await repo.editOccurrence(occ, scope, apply);
        } else {
          await repo.save(apply(occ.event));
        }
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l = L10n.of(context);
    final occ = widget.occurrence!;
    EditScope scope = EditScope.all;
    if (occ.isRecurring) {
      final s = await showEditScopeDialog(context, allowFollowing: !occ.isException);
      if (s == null) return;
      scope = s;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.deleteConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.delete)),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    await ref.read(eventRepositoryProvider).deleteOccurrence(occ, scope);
    if (mounted) Navigator.of(context).pop();
  }

  String _reminderLabel(L10n l, int m) {
    if (m == 0) return l.atStart;
    if (m % 1440 == 0) return l.daysBefore(m ~/ 1440);
    if (m % 60 == 0) return l.hoursBefore(m ~/ 60);
    return l.minutesBefore(m);
  }

  Future<void> _addReminder() async {
    final l = L10n.of(context);
    const options = [0, 5, 10, 15, 30, 60, 120, 1440, 2880];
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.addReminder),
        children: [
          for (final o in options)
            if (!_reminders.contains(o)) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o), child: Text(_reminderLabel(l, o))),
        ],
      ),
    );
    if (v != null) setState(() => _reminders = ([..._reminders, v]..sort()));
  }

  String _duration() {
    if (_allDay) {
      final days = Dates.startOfDay(_end).difference(Dates.startOfDay(_start)).inDays + 1;
      return '$days gün';
    }
    final m = _end.difference(_start).inMinutes;
    if (m <= 0) return '';
    if (m < 60) return '$m dk';
    return m % 60 == 0 ? '${m ~/ 60} saat' : '${m ~/ 60} sa ${m % 60} dk';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final calendars = (ref.watch(calendarsProvider).value ?? const <Calendar>[]).where((c) => c.source == 'local').toList();
    final allCalendars = ref.watch(calendarsProvider).value ?? const <Calendar>[];
    _isSubscription = allCalendars.any((c) => c.id == _calendarId && c.source == 'ics');
    final fmt = _allDay ? Dates.dayShort : Dates.dateTime;
    final notesStream = _event == null ? null : ref.watch(_eventNotesProvider(_event!.id));
    final readOnly = _readOnly;
    final calId = calendars.any((c) => c.id == _calendarId)
        ? _calendarId
        : (calendars.isEmpty ? null : calendars.firstWhere((c) => c.isDefault, orElse: () => calendars.first).id);
    final cal = allCalendars.where((c) => c.id == (_calendarId ?? calId)).firstOrNull;

    Widget field({required IconData icon, required Widget child, Widget? trailing, VoidCallback? onTap}) => InkWell(
          onTap: readOnly ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Row(children: [
              Icon(icon, size: 20, color: t.secondary),
              const SizedBox(width: Space.lg),
              Expanded(child: child),
              ?trailing,
            ]),
          ),
        );

    Widget group(List<Widget> children) => AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(), children[i]],
          ]),
        );

    Widget timeValue(String label, DateTime value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: context.text.bodySmall),
          Text(fmt.format(value), style: context.text.titleSmall?.copyWith(fontFeatures: tabularFigures)),
        ]);

    Future<void> pickCalendar() async {
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final c in calendars)
              ListTile(
                leading: Dot(colorFromHex(c.color), size: 12),
                title: Text(c.name),
                trailing: c.id == calId ? Icon(Icons.check_rounded, color: t.accent) : null,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ]),
        ),
      );
      if (picked != null) setState(() => _calendarId = picked);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 96,
          leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel, style: TextStyle(color: t.body))),
          title: Text(_isNew ? l.newEvent : l.eventTitle),
          actions: [
            if (!_isNew && !readOnly) IconButton(tooltip: l.delete, icon: Icon(Icons.delete_outline_rounded, color: t.secondary), onPressed: _delete),
            if (!readOnly) TextButton(onPressed: _saving ? null : _save, child: Text(l.save, style: TextStyle(color: t.accent))),
            const SizedBox(width: Space.sm),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.huge),
          children: [
            TextField(
              controller: _title,
              readOnly: readOnly,
              autofocus: _isNew,
              maxLines: null,
              style: context.text.headlineSmall,
              decoration: InputDecoration(
                hintText: l.titleHint,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              if (cal != null)
                Pill(neutral: true, leading: Dot(colorFromHex(cal.color)), label: cal.name, onTap: readOnly || calendars.length < 2 ? null : pickCalendar),
              Pill(
                neutral: _rrule == null,
                icon: Icons.repeat_rounded,
                label: _rrule == null ? l.noRepeat : describeRrule(_rrule),
                onTap: readOnly || (widget.occurrence?.isException ?? false)
                    ? null
                    : () async {
                        final r = await showRecurrencePicker(context, current: _rrule, start: _start);
                        setState(() => _rrule = r);
                      },
              ),
            ]),
            const SizedBox(height: Space.xl),
            group([
              field(
                icon: Icons.wb_sunny_outlined,
                child: Text(l.allDay, style: context.text.bodyLarge),
                trailing: Switch(value: _allDay, onChanged: readOnly ? null : (v) => setState(() => _allDay = v)),
              ),
              field(
                icon: Icons.schedule_rounded,
                child: timeValue(l.start, _start),
                trailing: Text(_duration(), style: context.text.bodySmall),
                onTap: () => _pick(true),
              ),
              field(icon: Icons.east_rounded, child: timeValue(l.end, _end), onTap: () => _pick(false)),
              if (!_allDay)
                field(icon: Icons.public_rounded, child: Text(_timezone, style: context.text.bodyMedium)),
            ]),
            const SizedBox(height: Space.lg),
            group([
              field(
                icon: Icons.place_outlined,
                child: TextField(
                  controller: _location,
                  readOnly: readOnly,
                  decoration: InputDecoration(
                    hintText: l.location,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
              field(
                icon: Icons.notifications_none_rounded,
                child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                  for (final m in _reminders)
                    Pill(
                      label: _reminderLabel(l, m),
                      onTap: readOnly ? null : () => setState(() => _reminders = _reminders.where((x) => x != m).toList()),
                    ),
                  if (!readOnly) Pill(neutral: true, icon: Icons.add_rounded, label: l.addReminder, onTap: _addReminder),
                ]),
              ),
              field(
                icon: Icons.notes_rounded,
                child: TextField(
                  controller: _description,
                  readOnly: readOnly,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: l.description,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
            ]),
            if (_event != null) ...[
              const SizedBox(height: Space.lg),
              for (final n in notesStream?.value ?? const <Note>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: AppCard.tight(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: n.id))),
                    child: Row(children: [
                      Icon(Icons.sticky_note_2_outlined, color: t.secondary),
                      const SizedBox(width: Space.md),
                      Expanded(child: Text(n.title.isEmpty ? l.untitled : n.title, style: context.text.titleSmall)),
                      Icon(Icons.chevron_right_rounded, color: t.faint),
                    ]),
                  ),
                ),
              AppCard.tight(
                shadow: false,
                color: t.accent5,
                border: Border.all(color: t.accent12),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(eventId: widget.occurrence!.seriesId)),
                ),
                child: Row(children: [
                  Icon(Icons.sticky_note_2_outlined, color: t.accent),
                  const SizedBox(width: Space.md),
                  Text(l.addNoteToEvent, style: context.text.titleSmall?.copyWith(color: t.accent)),
                ]),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: Text(_error!, style: context.text.bodySmall?.copyWith(color: t.danger)),
              ),
          ],
        ),
      ),
    );
  }
}

final _eventNotesProvider = StreamProvider.autoDispose.family<List<Note>, String>(
  (ref, id) => ref.watch(noteRepositoryProvider).watchByEvent(id),
);

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../core/theme.dart';
import '../../core/tz.dart';
import '../../data/db/database.dart';
import '../../data/repositories/repositories.dart';
import '../../data/sync/mappers.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../notes/note_editor_screen.dart';
import 'edit_scope_dialog.dart';
import 'recurrence_picker.dart';

/// Opens the editor for a new event on [initialStart] or for an existing [occurrence].
Future<void> openEventEditor(BuildContext context, {Occurrence? occurrence, DateTime? initialStart, bool allDay = false}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => EventEditorScreen(occurrence: occurrence, initialStart: initialStart, initialAllDay: allDay),
    fullscreenDialog: true,
  ));
}

class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.occurrence, this.initialStart, this.initialAllDay = false});
  final Occurrence? occurrence;
  final DateTime? initialStart;
  final bool initialAllDay;

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

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final calendars = (ref.watch(calendarsProvider).value ?? const <Calendar>[]).where((c) => c.source == 'local').toList();
    final allCalendars = ref.watch(calendarsProvider).value ?? const <Calendar>[];
    _isSubscription = allCalendars.any((c) => c.id == _calendarId && c.source == 'ics');
    final fmt = _allDay ? Dates.dayShort : Dates.dateTime;
    final notesStream = _event == null ? null : ref.watch(_eventNotesProvider(_event!.id));
    final readOnly = _readOnly;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? l.newEvent : l.edit),
          actions: [
            if (!_isNew && !readOnly) IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: _delete),
            if (!readOnly)
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(l.save),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextField(
              controller: _title,
              readOnly: readOnly,
              autofocus: _isNew,
              style: Theme.of(context).textTheme.titleLarge,
              decoration: InputDecoration(hintText: l.title, border: InputBorder.none),
              textInputAction: TextInputAction.next,
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.wb_sunny_outlined),
              title: Text(l.allDay),
              value: _allDay,
              onChanged: readOnly ? null : (v) => setState(() => _allDay = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(l.start),
              trailing: Text(fmt.format(_start)),
              onTap: readOnly ? null : () => _pick(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(l.end),
              trailing: Text(fmt.format(_end)),
              onTap: readOnly ? null : () => _pick(false),
            ),
            if (!_allDay)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.public),
                title: Text(l.timezone),
                trailing: Text(_timezone),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.repeat),
              title: Text(l.repeat),
              subtitle: _rrule == null ? null : Text(describeRrule(_rrule)),
              trailing: Text(_rrule == null ? l.noRepeat : ''),
              enabled: !readOnly && !(widget.occurrence?.isException ?? false),
              onTap: () async {
                final r = await showRecurrencePicker(context, current: _rrule, start: _start);
                setState(() => _rrule = r);
              },
            ),
            if (calendars.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(l.calendar),
                trailing: DropdownButton<String>(
                  value: calendars.any((c) => c.id == _calendarId)
                      ? _calendarId
                      : calendars.firstWhere((c) => c.isDefault, orElse: () => calendars.first).id,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in [...calendars, ...allCalendars.where((c) => c.source == 'ics' && c.id == _calendarId)])
                      DropdownMenuItem(
                        value: c.id,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.circle, size: 12, color: colorFromHex(c.color)),
                          const SizedBox(width: 8),
                          Text(c.name),
                        ]),
                      ),
                  ],
                  onChanged: readOnly ? null : (v) => setState(() => _calendarId = v),
                ),
              ),
            TextField(
              controller: _location,
              readOnly: readOnly,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.place_outlined), labelText: l.location, border: InputBorder.none),
            ),
            TextField(
              controller: _description,
              readOnly: readOnly,
              maxLines: null,
              minLines: 2,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.notes_outlined), labelText: l.description, border: InputBorder.none),
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.notifications_outlined),
                const SizedBox(width: 16),
                Text(l.reminders, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final m in _reminders)
                  InputChip(
                    label: Text(_reminderLabel(l, m)),
                    onDeleted: readOnly ? null : () => setState(() => _reminders = _reminders.where((x) => x != m).toList()),
                  ),
                if (!readOnly) ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(l.addReminder), onPressed: _addReminder),
              ],
            ),
            if (_event != null) ...[
              const Divider(),
              Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined),
                  const SizedBox(width: 16),
                  Text(l.notes, style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(l.addNote),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(eventId: _event!.id)),
                    ),
                  ),
                ],
              ),
              for (final n in notesStream?.value ?? const <Note>[])
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.notes, size: 18),
                  title: Text(n.title.isEmpty ? l.untitled : n.title),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: n.id))),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

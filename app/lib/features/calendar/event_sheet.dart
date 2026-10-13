import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Minimal create/edit sheet (title, calendar, start, end, all-day, location).
/// The full editor with recurrence and reminders arrives in phase 3.
Future<void> showEventSheet(BuildContext context, WidgetRef ref, {Event? event, DateTime? initialDay}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EventSheet(event: event, initialDay: initialDay),
  );
}

class _EventSheet extends ConsumerStatefulWidget {
  const _EventSheet({this.event, this.initialDay});
  final Event? event;
  final DateTime? initialDay;

  @override
  ConsumerState<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<_EventSheet> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
  String? _calendarId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    if (e != null) {
      _start = e.startAt.toLocal();
      _end = e.endAt.toLocal();
      _allDay = e.allDay;
      _calendarId = e.calendarId;
    } else {
      final day = widget.initialDay ?? Dates.startOfDay(DateTime.now());
      final now = DateTime.now();
      final hour = Dates.sameDay(day, now) ? (now.hour + 1).clamp(0, 23) : 9;
      _start = DateTime(day.year, day.month, day.day, hour);
      _end = _start.add(const Duration(hours: 1));
      _allDay = false;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final base = start ? _start : _end;
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
      if (start) {
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
    if (end.isBefore(start)) {
      setState(() => _error = l.endBeforeStart);
      return;
    }
    final repo = ref.read(eventRepositoryProvider);
    final calId = _calendarId ?? (await ref.read(calendarRepositoryProvider).ensureDefault()).id;
    final tz = DateTime.now().timeZoneName; // phase 3: proper IANA via package; server accepts UTC fallback
    if (widget.event == null) {
      await repo.create(
        calendarId: calId,
        title: _title.text,
        startAt: start,
        endAt: end,
        timezone: _ianaOrUtc(tz),
        location: _location.text.trim(),
        allDay: _allDay,
      );
    } else {
      await repo.save(widget.event!.copyWith(
        calendarId: calId,
        title: _title.text,
        startAt: start.toUtc(),
        endAt: end.toUtc(),
        location: _location.text.trim(),
        allDay: _allDay,
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  // Dart only exposes the abbreviation (e.g. "+03"); the real IANA zone comes in phase 3.
  String _ianaOrUtc(String abbr) => abbr.contains('/') ? abbr : 'Europe/Istanbul';

  Future<void> _delete() async {
    final l = L10n.of(context);
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
    if (ok != true || !mounted) return;
    await ref.read(eventRepositoryProvider).remove(widget.event!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final calendars = ref.watch(calendarsProvider).value ?? const <Calendar>[];
    final fmt = _allDay ? Dates.dayShort : Dates.dateTime;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(widget.event == null ? l.newEvent : l.edit, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (widget.event != null) IconButton(icon: const Icon(Icons.delete_outline), tooltip: l.delete, onPressed: _delete),
            ],
          ),
          TextField(controller: _title, autofocus: true, decoration: InputDecoration(labelText: l.title), textInputAction: TextInputAction.next),
          const SizedBox(height: 8),
          TextField(controller: _location, decoration: InputDecoration(labelText: l.location)),
          const SizedBox(height: 8),
          if (calendars.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _calendarId ?? calendars.firstWhere((c) => c.isDefault, orElse: () => calendars.first).id,
              decoration: InputDecoration(labelText: l.calendar),
              items: [
                for (final c in calendars)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(children: [
                      Icon(Icons.circle, size: 12, color: colorFromHex(c.color)),
                      const SizedBox(width: 8),
                      Text(c.name),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => _calendarId = v),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.allDay),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(l.start),
            trailing: Text(fmt.format(_start)),
            onTap: () => _pick(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(l.end),
            trailing: Text(fmt.format(_end)),
            onTap: () => _pick(false),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: Text(l.save)),
            ],
          ),
        ],
      ),
    );
  }
}

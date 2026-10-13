import 'package:flutter/material.dart';
import 'package:rrule/rrule.dart';

import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../l10n/app_localizations.dart';

enum _Preset { none, daily, weekly, monthly, yearly, custom }

/// Returns the chosen RRULE string (null = no repeat) or the input if cancelled.
Future<String?> showRecurrencePicker(BuildContext context, {String? current, required DateTime start}) async {
  final result = await showModalBottomSheet<_Result>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RecurrenceSheet(current: current, start: start),
  );
  return result == null ? current : result.rrule;
}

class _Result {
  _Result(this.rrule);
  final String? rrule;
}

class _RecurrenceSheet extends StatefulWidget {
  const _RecurrenceSheet({this.current, required this.start});
  final String? current;
  final DateTime start;

  @override
  State<_RecurrenceSheet> createState() => _RecurrenceSheetState();
}

class _RecurrenceSheetState extends State<_RecurrenceSheet> {
  _Preset _preset = _Preset.none;
  Frequency _freq = Frequency.weekly;
  int _interval = 1;
  final Set<int> _weekdays = {}; // DateTime.monday..sunday
  int _endMode = 0; // 0 never, 1 count, 2 until
  int _count = 10;
  DateTime? _until;

  @override
  void initState() {
    super.initState();
    final r = parseRrule(widget.current);
    if (r == null) {
      _weekdays.add(widget.start.toLocal().weekday);
      return;
    }
    _freq = r.frequency;
    _interval = r.interval ?? 1;
    _weekdays.addAll(r.byWeekDays.map((d) => d.day));
    if (_weekdays.isEmpty) _weekdays.add(widget.start.toLocal().weekday);
    if (r.count != null) {
      _endMode = 1;
      _count = r.count!;
    } else if (r.until != null) {
      _endMode = 2;
      _until = DateTime(r.until!.year, r.until!.month, r.until!.day);
    }
    final simple = _interval == 1 && _endMode == 0;
    if (simple && _freq == Frequency.daily) {
      _preset = _Preset.daily;
    } else if (simple && _freq == Frequency.weekly && _weekdays.length == 1 && _weekdays.first == widget.start.toLocal().weekday) {
      _preset = _Preset.weekly;
    } else if (simple && _freq == Frequency.monthly && r.byMonthDays.isEmpty) {
      _preset = _Preset.monthly;
    } else if (simple && _freq == Frequency.yearly) {
      _preset = _Preset.yearly;
    } else {
      _preset = _Preset.custom;
    }
  }

  String? _build() {
    switch (_preset) {
      case _Preset.none:
        return null;
      case _Preset.daily:
        return 'FREQ=DAILY';
      case _Preset.weekly:
        return 'FREQ=WEEKLY';
      case _Preset.monthly:
        return 'FREQ=MONTHLY';
      case _Preset.yearly:
        return 'FREQ=YEARLY';
      case _Preset.custom:
        final r = RecurrenceRule(
          frequency: _freq,
          interval: _interval == 1 ? null : _interval,
          count: _endMode == 1 ? _count : null,
          until: _endMode == 2 && _until != null ? DateTime.utc(_until!.year, _until!.month, _until!.day, 23, 59, 59) : null,
          byWeekDays: _freq == Frequency.weekly ? (_weekdays.toList()..sort()).map((d) => ByWeekDayEntry(d)).toList() : const [],
          weekStart: DateTime.monday,
        );
        return rruleToString(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const dayLabels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final presets = [
      (_Preset.none, l.noRepeat),
      (_Preset.daily, l.daily),
      (_Preset.weekly, l.weekly),
      (_Preset.monthly, l.monthly),
      (_Preset.yearly, l.yearly),
      (_Preset.custom, l.custom),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.repeat, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final p in presets)
                  ChoiceChip(label: Text(p.$2), selected: _preset == p.$1, onSelected: (_) => setState(() => _preset = p.$1)),
              ],
            ),
            if (_preset == _Preset.custom) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(l.every),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 64,
                    child: TextFormField(
                      initialValue: '$_interval',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (v) => setState(() => _interval = (int.tryParse(v) ?? 1).clamp(1, 999)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<Frequency>(
                    value: _freq,
                    items: [
                      DropdownMenuItem(value: Frequency.daily, child: Text(l.unitDays)),
                      DropdownMenuItem(value: Frequency.weekly, child: Text(l.unitWeeks)),
                      DropdownMenuItem(value: Frequency.monthly, child: Text(l.unitMonths)),
                      DropdownMenuItem(value: Frequency.yearly, child: Text(l.unitYears)),
                    ],
                    onChanged: (v) => setState(() => _freq = v ?? _freq),
                  ),
                ],
              ),
              if (_freq == Frequency.weekly) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 1; i <= 7; i++)
                      FilterChip(
                        label: Text(dayLabels[i - 1]),
                        selected: _weekdays.contains(i),
                        onSelected: (s) => setState(() {
                          if (s) {
                            _weekdays.add(i);
                          } else if (_weekdays.length > 1) {
                            _weekdays.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(l.ends, style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<int>(
                groupValue: _endMode,
                onChanged: (v) => setState(() => _endMode = v ?? 0),
                child: Column(
                  children: [
                    RadioListTile<int>(value: 0, title: Text(l.never), contentPadding: EdgeInsets.zero),
                    RadioListTile<int>(
                      value: 1,
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: TextFormField(
                              initialValue: '$_count',
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onChanged: (v) => setState(() => _count = (int.tryParse(v) ?? 1).clamp(1, 9999)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(l.afterCount(_count).replaceFirst('$_count ', '')),
                        ],
                      ),
                    ),
                    RadioListTile<int>(
                      value: 2,
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          Text(l.onDate),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _until ?? widget.start.toLocal().add(const Duration(days: 30)),
                                firstDate: widget.start.toLocal(),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) {
                                setState(() {
                                  _until = d;
                                  _endMode = 2;
                                });
                              }
                            },
                            child: Text(_until == null ? '…' : Dates.dayShort.format(_until!)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(describeRrule(_build()), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => Navigator.pop(context, _Result(_build())), child: Text(l.done)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

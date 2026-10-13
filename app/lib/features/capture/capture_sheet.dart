import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capture_parser.dart';
import '../../core/dates.dart';
import '../../core/recurrence.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../calendar/event_editor_screen.dart';
import '../notes/note_editor_screen.dart';

/// Opens the one-line quick capture sheet, optionally prefilled (share / widget).
Future<void> showCaptureSheet(BuildContext context, {String? initialText}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CaptureSheet(initialText: initialText),
  );
}

class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key, this.initialText, this.onSaved});
  final String? initialText;
  final VoidCallback? onSaved;

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  late final TextEditingController _text;
  final _parser = CaptureParser();
  CaptureResult? _result;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText ?? '');
    _reparse();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reparse() => setState(() => _result = _text.text.trim().isEmpty ? null : _parser.parse(_text.text));

  Future<void> _saveTask() async {
    final r = _result;
    if (r == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(taskRepositoryProvider).create(
            title: r.title.isEmpty ? _text.text.trim() : r.title,
            dueAt: r.isEvent && !r.allDay ? r.start : (r.isEvent ? r.start!.add(const Duration(hours: 9)) : null),
          );
      widget.onSaved?.call();
      if (mounted) {
        final l = L10n.of(context);
        Navigator.of(context).pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l.captureSaved), duration: const Duration(seconds: 1)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save({bool forceNote = false}) async {
    final r = _result;
    if (r == null || _saving) return;
    setState(() => _saving = true);
    try {
      if (r.isEvent && !forceNote) {
        final cal = await ref.read(calendarRepositoryProvider).ensureDefault();
        await ref.read(eventRepositoryProvider).create(
              calendarId: cal.id,
              title: r.title,
              startAt: r.start!,
              endAt: r.end!,
              allDay: r.allDay,
              location: r.location,
              rrule: r.rrule,
              reminders: r.reminders,
            );
      } else {
        await ref.read(noteRepositoryProvider).create(
              title: r.title.isEmpty ? _text.text.trim().split('\n').first : r.title,
              body: r.isEvent ? _text.text.trim() : r.body,
            );
      }
      widget.onSaved?.call();
      if (mounted) {
        final l = L10n.of(context);
        Navigator.of(context).pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l.captureSaved), duration: const Duration(seconds: 1)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Opens the full editor prefilled with the parsed result (chip tap).
  Future<void> _edit() async {
    final r = _result;
    if (r == null) return;
    Navigator.of(context).pop();
    if (r.isEvent) {
      await openEventEditor(context, initialStart: r.start, allDay: r.allDay, prefill: r);
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(initialTitle: r.title, initialBody: r.body)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final r = _result;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt),
              const SizedBox(width: 8),
              Text(l.quickCapture, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): _save,
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
              const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => _save(forceNote: true),
            },
            child: TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: l.captureHint, prefixIcon: const Icon(Icons.edit_outlined)),
              onChanged: (_) => _reparse(),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(height: 8),
          if (r == null)
            Text(l.captureExamples, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: Icon(r.isEvent ? Icons.event : Icons.notes, size: 18),
                  label: Text(r.isEvent ? '${l.captureEvent}: ${r.title}' : '${l.captureNote}: ${r.title.isEmpty ? l.untitled : r.title}'),
                  onPressed: _edit,
                  backgroundColor: scheme.primaryContainer,
                ),
                if (r.isEvent)
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text(r.allDay
                        ? Dates.dayShort.format(r.start!)
                        : '${Dates.dateTime.format(r.start!)} – ${Dates.sameDay(r.start!, r.end!) ? Dates.time.format(r.end!) : Dates.dateTime.format(r.end!)}'),
                    onPressed: _edit,
                  ),
                if (r.location.isNotEmpty) ActionChip(avatar: const Icon(Icons.place_outlined, size: 18), label: Text(r.location), onPressed: _edit),
                if (r.rrule != null) ActionChip(avatar: const Icon(Icons.repeat, size: 18), label: Text(describeRrule(r.rrule)), onPressed: _edit),
                for (final m in r.reminders)
                  ActionChip(avatar: const Icon(Icons.notifications_outlined, size: 18), label: Text(l.minutesBefore(m)), onPressed: _edit),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (r != null)
                TextButton(onPressed: _saving ? null : _saveTask, child: Text(l.captureSaveTask)),
              if (r != null && r.isEvent)
                TextButton(onPressed: _saving ? null : () => _save(forceNote: true), child: Text(l.captureSaveNote)),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: r == null || _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(r?.isEvent ?? false ? l.captureSaveEvent : l.captureSaveNote),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

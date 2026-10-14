import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capture_parser.dart';
import '../../core/dates.dart';
import '../../core/platform_info.dart';
import '../../core/recurrence.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../calendar/event_editor_screen.dart';
import '../notes/note_editor_screen.dart';

/// What the primary button saves when the parser has no strong opinion.
enum CaptureTarget { auto, note, task }

/// Opens the quick capture sheet.
///
/// [target] picks the primary action (Notes tab → note, Tasks tab → task);
/// [baseDay] makes "15:00 toplantı" land on the day selected in the calendar.
Future<void> showCaptureSheet(BuildContext context, {String? initialText, CaptureTarget target = CaptureTarget.auto, DateTime? baseDay}) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CaptureSheet(initialText: initialText, target: target, baseDay: baseDay, messenger: messenger),
  );
}

class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key, this.initialText, this.target = CaptureTarget.auto, this.baseDay, this.messenger});
  final String? initialText;
  final CaptureTarget target;
  final DateTime? baseDay;
  final ScaffoldMessengerState? messenger;

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  late final _HighlightController _text;
  late final CaptureParser _parser;
  CaptureResult? _result;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final base = widget.baseDay;
    _parser = CaptureParser(
      now: base == null || Dates.sameDay(base, DateTime.now())
          ? DateTime.now
          : () => DateTime(base.year, base.month, base.day),
    );
    _text = _HighlightController(text: widget.initialText ?? '');
    _reparse();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reparse() {
    final r = _text.text.trim().isEmpty ? null : _parser.parse(_text.text);
    _text.parts = r?.matched.map((m) => m.text).toList() ?? const [];
    setState(() => _result = r);
  }

  /// The kind the primary button saves.
  CaptureTarget get _primary {
    if (widget.target != CaptureTarget.auto) return widget.target;
    return (_result?.isEvent ?? false) ? CaptureTarget.auto : CaptureTarget.note;
  }

  Future<void> _save(CaptureTarget kind) async {
    final r = _result;
    if (r == null || _saving) return;
    setState(() => _saving = true);
    final l = L10n.of(context);
    final t = context.tokens;
    try {
      late final String title;
      String? subtitle;
      late final Future<void> Function() undo;
      switch (kind) {
        case CaptureTarget.auto when r.isEvent:
          final cal = await ref.read(calendarRepositoryProvider).ensureDefault();
          final repo = ref.read(eventRepositoryProvider);
          final e = await repo.create(
            calendarId: cal.id,
            title: r.title,
            startAt: r.start!,
            endAt: r.end!,
            allDay: r.allDay,
            location: r.location,
            rrule: r.rrule,
            reminders: r.reminders.isEmpty && !r.allDay ? const [10] : r.reminders,
          );
          title = l.savedEvent;
          final first = (r.reminders.isEmpty && !r.allDay ? const [10] : r.reminders).fold<int>(0, (a, b) => a > b ? a : b);
          subtitle = r.allDay ? Dates.dayShort.format(r.start!) : l.willRemindAt(Dates.dateTime.format(r.start!.subtract(Duration(minutes: first))));
          undo = () => repo.remove(e.id);
        case CaptureTarget.task:
          final repo = ref.read(taskRepositoryProvider);
          final due = r.isEvent ? (r.allDay ? r.start!.add(const Duration(hours: 9)) : r.start) : null;
          final task = await repo.create(title: r.title.isEmpty ? _text.text.trim() : r.title, dueAt: due);
          title = l.savedTask;
          subtitle = due == null ? null : Dates.dateTime.format(due);
          undo = () => repo.remove(task.id);
        default:
          final repo = ref.read(noteRepositoryProvider);
          final n = await repo.create(
            title: r.title.isEmpty ? _text.text.trim().split('\n').first : r.title,
            body: r.isEvent ? _text.text.trim() : r.body,
          );
          title = l.savedNote;
          undo = () => repo.remove(n.id);
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop();
      (widget.messenger ?? ScaffoldMessenger.maybeOf(context))?.showSnackBar(_savedSnack(l, t, title, subtitle, undo));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SnackBar _savedSnack(L10n l, AppTokens t, String title, String? subtitle, Future<void> Function() undo) {
    return SnackBar(
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.huge + Space.huge),
      padding: const EdgeInsets.all(Space.lg),
      content: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: t.success,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: t.success.withValues(alpha: .6), blurRadius: 24)],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: TypeScale.md, color: Colors.white)),
            if (subtitle != null)
              Text(subtitle, style: const TextStyle(fontFamily: 'Inter', fontSize: TypeScale.sm, color: Colors.white70, fontFeatures: tabularFigures)),
          ]),
        ),
      ]),
      action: SnackBarAction(label: l.undo, onPressed: () => undo()),
    );
  }

  /// Opens the full editor prefilled with the parsed result (chip tap).
  Future<void> _edit() async {
    final r = _result;
    if (r == null) return;
    final nav = Navigator.of(context);
    nav.pop();
    if (r.isEvent && widget.target != CaptureTarget.note) {
      await openEventEditor(nav.context, initialStart: r.start, allDay: r.allDay, prefill: r);
    } else {
      await nav.push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(initialTitle: r.title, initialBody: r.body)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final r = _result;
    final primary = _primary;
    final primaryLabel = switch (primary) {
      CaptureTarget.task => l.captureSaveTask,
      CaptureTarget.note => l.captureSaveNote,
      CaptureTarget.auto => l.captureSaveEvent,
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(l.quickCapture, style: context.text.titleLarge)),
            if (PlatformInfo.isDesktop || PlatformInfo.isWeb) Text(l.captureKeysHint, style: context.text.bodySmall),
          ]),
          const SizedBox(height: Space.lg),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () => _save(primary),
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => _save(primary),
              const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => _save(CaptureTarget.note),
            },
            child: TextField(
              controller: _text,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w400),
              decoration: InputDecoration(hintText: l.captureHint),
              onChanged: (_) => _reparse(),
              onSubmitted: (_) => _save(primary),
            ),
          ),
          const SizedBox(height: Space.lg),
          if (r == null)
            Text(l.captureExamples, style: context.text.bodySmall)
          else ...[
            Text(l.captureUnderstood, style: context.text.bodySmall),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: _chips(context, l, r)),
          ],
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: r == null || _saving ? null : () => _save(primary),
            style: FilledButton.styleFrom(shadowColor: t.accent.withValues(alpha: .4), elevation: r == null ? 0 : 6),
            child: Text(primaryLabel),
          ),
          const SizedBox(height: Space.sm),
          Row(children: [
            if (primary != CaptureTarget.auto && (r?.isEvent ?? false)) ...[
              Expanded(child: OutlinedButton(onPressed: _saving ? null : () => _save(CaptureTarget.auto), child: Text(l.captureEvent))),
              const SizedBox(width: Space.sm),
            ],
            if (primary != CaptureTarget.task) ...[
              Expanded(child: OutlinedButton(onPressed: r == null || _saving ? null : () => _save(CaptureTarget.task), child: Text(l.captureTask))),
              const SizedBox(width: Space.sm),
            ],
            if (primary != CaptureTarget.note)
              Expanded(child: OutlinedButton(onPressed: r == null || _saving ? null : () => _save(CaptureTarget.note), child: Text(l.captureNoteShort))),
          ]),
        ],
      ),
    );
  }

  List<Widget> _chips(BuildContext context, L10n l, CaptureResult r) {
    final asEvent = r.isEvent && widget.target != CaptureTarget.note;
    return [
      Pill(
        icon: switch (widget.target) {
          CaptureTarget.task => Icons.check_circle_outline,
          CaptureTarget.note => Icons.notes_rounded,
          CaptureTarget.auto => asEvent ? Icons.event_outlined : Icons.notes_rounded,
        },
        label: r.title.isEmpty ? l.untitled : r.title,
        onTap: _edit,
      ),
      if (r.isEvent)
        Pill(
          icon: Icons.schedule_rounded,
          label: r.allDay
              ? Dates.dayShort.format(r.start!)
              : '${Dates.dateTime.format(r.start!)} – ${Dates.sameDay(r.start!, r.end!) ? Dates.time.format(r.end!) : Dates.dateTime.format(r.end!)}',
          onTap: _edit,
        ),
      if (r.location.isNotEmpty) Pill(icon: Icons.place_outlined, label: r.location, onTap: _edit),
      if (r.rrule != null) Pill(icon: Icons.repeat_rounded, label: describeRrule(r.rrule), onTap: _edit),
      for (final m in r.reminders) Pill(icon: Icons.notifications_none_rounded, label: l.minutesBefore(m), onTap: _edit),
    ];
  }
}

/// Text controller that highlights the parts the parser recognised.
class _HighlightController extends TextEditingController {
  _HighlightController({super.text});

  List<String> parts = const [];

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (parts.isEmpty || text.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final t = context.tokens;
    // the parser works on a Turkish-lowercased copy of the same length
    final lower = text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    final ranges = <(int, int)>[];
    for (final p in parts) {
      final i = lower.indexOf(p.toLowerCase());
      if (i >= 0) ranges.add((i, i + p.length));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <InlineSpan>[];
    var pos = 0;
    final mark = style?.copyWith(color: t.accent, fontWeight: FontWeight.w600, backgroundColor: t.accent12);
    for (final (s, e) in ranges) {
      if (s < pos || e > text.length) continue;
      if (s > pos) spans.add(TextSpan(text: text.substring(pos, s)));
      spans.add(TextSpan(text: text.substring(s, e), style: mark));
      pos = e;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: spans);
  }
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../capture/capture_sheet.dart';
import '../home/shell_actions.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../notes/note_editor_screen.dart';

/// To-do list: progress ring, then Overdue / Today / Later / Done groups.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => TasksScreenState();
}

class TasksScreenState extends ConsumerState<TasksScreen> {
  bool _showDone = false;

  Future<void> createTask() => showTaskSheet(context, ref);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final now = DateTime.now();
    final today = Dates.startOfDay(now);
    final tomorrow = today.add(const Duration(days: 1));
    final open = tasks.where((x) => !x.done).toList();
    final overdue = open.where((x) => x.dueAt != null && x.dueAt!.toLocal().isBefore(today)).toList();
    final dueToday = open.where((x) => x.dueAt != null && !x.dueAt!.toLocal().isBefore(today) && x.dueAt!.toLocal().isBefore(tomorrow)).toList();
    final later = open.where((x) => x.dueAt == null || !x.dueAt!.toLocal().isBefore(tomorrow)).toList();
    final done = tasks.where((x) => x.done).toList();
    final doneToday = done.where((x) => x.dueAt != null && x.dueAt!.toLocal().isBefore(tomorrow) && Dates.sameDay(x.updatedAt, now)).toList();

    // progress of what was on today's plate (overdue + due today + done today)
    final planned = overdue.length + dueToday.length + doneToday.length;
    final remaining = overdue.length + dueToday.length;
    final progressTitle = planned == 0
        ? l.tasksNoneToday
        : remaining == 0
            ? l.tasksAllDone
            : doneToday.isEmpty
                ? l.tasksStart
                : l.tasksGoingWell;
    final progressSub = [
      if (remaining > 0) l.tasksRemaining(remaining),
      if (overdue.isNotEmpty) l.overdueCount(overdue.length),
    ].join(' · ');

    Widget group(List<Task> items) => AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
          radius: Radii.lg,
          child: Column(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(indent: 52),
              _TaskTile(items[i], now: now),
            ],
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(title: l.tabTasks, trailing: const ShellActions()),
      Expanded(
        child: tasks.isEmpty || (open.isEmpty && !_showDone && done.isEmpty)
            ? EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: l.emptyTasksTitle,
                message: l.emptyTasksBody,
                examples: [l.exampleTask1, l.exampleTask2],
                onExample: (e) => showCaptureSheet(context, initialText: e, target: CaptureTarget.task),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg), children: [
                AppCard(
                  child: Row(children: [
                    ProgressRing(value: planned == 0 ? 1 : doneToday.length / planned, label: '${doneToday.length}/$planned'),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(progressTitle, style: context.text.titleLarge),
                        if (progressSub.isNotEmpty) Text(progressSub, style: context.text.bodySmall),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: Space.xl),
                if (overdue.isNotEmpty) ...[
                  SectionHeader(l.overdue, icon: Icons.flag_outlined, color: t.danger, small: true),
                  group(overdue),
                  const SizedBox(height: Space.xl),
                ],
                if (dueToday.isNotEmpty || doneToday.isNotEmpty) ...[
                  SectionHeader(l.today, small: true),
                  group([...dueToday, ...doneToday]),
                  const SizedBox(height: Space.xl),
                ],
                if (later.isNotEmpty) ...[
                  SectionHeader(l.later, small: true),
                  group(later),
                  const SizedBox(height: Space.xl),
                ],
                if (done.length > doneToday.length) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: () => setState(() => _showDone = !_showDone),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(children: [
                        Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: t.secondary),
                        const SizedBox(width: Space.sm),
                        Text('${l.doneSection} · ${done.length - doneToday.length}', style: context.text.bodySmall),
                      ]),
                    ),
                  ),
                  if (_showDone) ...[
                    const SizedBox(height: Space.sm),
                    group(done.where((x) => !doneToday.contains(x)).toList()),
                  ],
                ],
              ]),
      ),
    ]);
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile(this.task, {required this.now});
  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final t = context.tokens;
    final repo = ref.read(taskRepositoryProvider);
    final overdue = !task.done && task.dueAt != null && task.dueAt!.isBefore(now);
    final linkedNote = task.noteId == null ? null : ref.watch(notesProvider).value?.where((n) => n.id == task.noteId).firstOrNull;
    final meta = [
      if (task.dueAt != null)
        Dates.sameDay(task.dueAt!, now) ? Dates.time.format(task.dueAt!.toLocal()) : Dates.dateTime.format(task.dueAt!.toLocal()),
    ];
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.lg),
        child: Icon(Icons.delete_outline_rounded, color: t.danger),
      ),
      onDismissed: (_) {
        repo.remove(task.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.taskDeleted)));
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => showTaskSheet(context, ref, task: task),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(children: [
            PopCheck(value: task.done, danger: overdue, onChanged: (v) => repo.setDone(task.id, v)),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.title,
                    style: task.done
                        ? context.text.bodyLarge?.copyWith(color: t.faint, decoration: TextDecoration.lineThrough)
                        : context.text.bodyLarge?.copyWith(color: t.ink)),
                if (meta.isNotEmpty || linkedNote != null)
                  Text.rich(
                    TextSpan(children: [
                      if (meta.isNotEmpty) TextSpan(text: meta.first, style: TextStyle(color: overdue ? t.danger : null)),
                      if (meta.isNotEmpty && linkedNote != null) const TextSpan(text: ' · '),
                      if (linkedNote != null)
                        TextSpan(
                          text: linkedNote.title.isEmpty ? l.untitled : linkedNote.title,
                          style: TextStyle(color: t.accent, fontWeight: FontWeight.w600),
                        ),
                    ]),
                    style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                  ),
              ]),
            ),
            if (linkedNote != null)
              IconButton(
                icon: Icon(Icons.sticky_note_2_outlined, size: 20, color: t.secondary),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: linkedNote.id))),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Create/edit sheet: title, optional due date, optional linked note.
Future<void> showTaskSheet(BuildContext context, WidgetRef ref, {Task? task, String? initialTitle, DateTime? initialDue, String? noteId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TaskSheet(task: task, initialTitle: initialTitle, initialDue: initialDue, noteId: noteId),
  );
}

class _TaskSheet extends ConsumerStatefulWidget {
  const _TaskSheet({this.task, this.initialTitle, this.initialDue, this.noteId});
  final Task? task;
  final String? initialTitle;
  final DateTime? initialDue;
  final String? noteId;

  @override
  ConsumerState<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<_TaskSheet> {
  late final TextEditingController _title;
  DateTime? _due;
  String? _noteId;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task?.title ?? widget.initialTitle ?? '');
    _due = widget.task?.dueAt?.toLocal() ?? widget.initialDue;
    _noteId = widget.task?.noteId ?? widget.noteId;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final d = await showDatePicker(context: context, initialDate: _due ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? DateTime(d.year, d.month, d.day, 9)),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (!mounted) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    if (widget.task == null) {
      await repo.create(title: _title.text, dueAt: _due, noteId: _noteId);
    } else {
      await repo.save(widget.task!.copyWith(title: _title.text, dueAt: Value(_due?.toUtc()), noteId: Value(_noteId)));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.task == null ? l.newTask : l.edit, style: Theme.of(context).textTheme.titleLarge),
          TextField(controller: _title, autofocus: true, decoration: InputDecoration(hintText: l.taskTitleHint), onSubmitted: (_) => _save()),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(l.dueDate),
            trailing: Text(_due == null ? l.noDueDate : Dates.dateTime.format(_due!)),
            onTap: _pickDue,
            onLongPress: () => setState(() => _due = null),
          ),
          if (notes.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: notes.any((n) => n.id == _noteId) ? _noteId : null,
              decoration: InputDecoration(labelText: l.linkedNote, prefixIcon: const Icon(Icons.notes_outlined)),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l.none)),
                for (final n in notes.take(50)) DropdownMenuItem(value: n.id, child: Text(n.title.isEmpty ? l.untitled : n.title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _noteId = v),
            ),
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

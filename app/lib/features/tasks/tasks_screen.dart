import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../notes/note_editor_screen.dart';

/// To-do list: open tasks first (overdue highlighted), done tasks collapsible.
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
    final scheme = Theme.of(context).colorScheme;
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final open = tasks.where((t) => !t.done).toList();
    final done = tasks.where((t) => t.done).toList();
    final now = DateTime.now();
    if (tasks.isEmpty) {
      return Center(child: Text(l.noTasks, style: TextStyle(color: scheme.outline)));
    }
    return ListView(
      children: [
        for (final t in open) _tile(context, t, now),
        if (done.isNotEmpty)
          ListTile(
            leading: Icon(_showDone ? Icons.expand_less : Icons.expand_more),
            title: Text('${_showDone ? l.hideDone : l.showDone} (${done.length})'),
            onTap: () => setState(() => _showDone = !_showDone),
          ),
        if (_showDone) for (final t in done) _tile(context, t, now),
      ],
    );
  }

  Widget _tile(BuildContext context, Task t, DateTime now) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final overdue = !t.done && t.dueAt != null && t.dueAt!.isBefore(now);
    final repo = ref.read(taskRepositoryProvider);
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(color: scheme.errorContainer, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete_outline)),
      onDismissed: (_) {
        repo.remove(t.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.taskDeleted)));
      },
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: t.done,
        onChanged: (v) => repo.setDone(t.id, v ?? false),
        title: Text(t.title, style: t.done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: t.dueAt == null && t.noteId == null
            ? null
            : Row(children: [
                if (t.dueAt != null)
                  Text(
                    '${overdue ? '${l.overdue} · ' : ''}${Dates.dateTime.format(t.dueAt!.toLocal())}',
                    style: TextStyle(color: overdue ? scheme.error : null),
                  ),
                if (t.noteId != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: t.noteId))),
                    child: Icon(Icons.notes, size: 16, color: scheme.primary),
                  ),
                ],
              ]),
        secondary: IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => showTaskSheet(context, ref, task: t)),
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

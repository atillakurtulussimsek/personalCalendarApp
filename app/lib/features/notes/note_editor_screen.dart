import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/repositories/repositories.dart';
import '../../data/sync/mappers.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Markdown note editor with autosave (debounced) and a preview toggle.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.noteId, this.eventId, this.initialTitle, this.initialBody});
  final String? noteId;
  final String? eventId;
  final String? initialTitle;
  final String? initialBody;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tags = TextEditingController();
  final _bodyFocus = FocusNode();
  Note? _note;
  bool _preview = false;
  bool _pinned = false;
  bool _loaded = false;
  bool _dirty = false;
  Timer? _autosave;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.noteId == null) {
      if (widget.initialTitle != null) _title.text = widget.initialTitle!;
      if (widget.initialBody != null) _body.text = widget.initialBody!;
      if (_title.text.isNotEmpty || _body.text.isNotEmpty) _dirty = true;
    }
    if (widget.noteId != null) {
      final n = await ref.read(noteRepositoryProvider).get(widget.noteId!);
      if (n != null) {
        _note = n;
        _title.text = n.title;
        _body.text = n.body;
        _tags.text = noteTags(n).join(', ');
        _pinned = n.pinned;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    unawaited(_flush());
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _changed() {
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 1), _flush);
  }

  /// Persists the current text if anything changed. Empty new notes are not created.
  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    final repo = ref.read(noteRepositoryProvider);
    final title = _title.text;
    final body = _body.text;
    final tags = NoteRepository.normalizeTags(_tags.text.split(','));
    if (_note == null) {
      if (title.trim().isEmpty && body.trim().isEmpty) return;
      _note = await repo.create(title: title, body: body, tags: tags, eventId: widget.eventId, pinned: _pinned);
      return;
    }
    final updated = _note!.copyWith(title: title, body: body, pinned: _pinned, tags: jsonEncode(tags));
    await repo.save(updated);
    _note = (await repo.get(_note!.id)) ?? updated;
  }

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
    _dirty = false;
    _autosave?.cancel();
    if (_note != null) await ref.read(noteRepositoryProvider).remove(_note!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _flush,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _flush,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true): () => setState(() => _preview = !_preview),
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _title,
            decoration: InputDecoration(hintText: l.title, border: InputBorder.none),
            style: Theme.of(context).textTheme.titleLarge,
            onChanged: (_) => _changed(),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _bodyFocus.requestFocus(),
          ),
          actions: [
            IconButton(
              tooltip: _pinned ? l.unpin : l.pin,
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () {
                setState(() => _pinned = !_pinned);
                _changed();
              },
            ),
            IconButton(
              tooltip: _preview ? l.edit : l.preview,
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _preview = !_preview),
            ),
            IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _preview
                  ? Markdown(data: _body.text, selectable: true, padding: const EdgeInsets.all(16))
                  : TextField(
                      controller: _body,
                      focusNode: _bodyFocus,
                      autofocus: widget.noteId == null,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: l.noteBodyHint,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 15, height: 1.4),
                      onChanged: (_) => _changed(),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _tags,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.tag, size: 18), hintText: l.tags, isDense: true, border: InputBorder.none),
                onChanged: (_) => _changed(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

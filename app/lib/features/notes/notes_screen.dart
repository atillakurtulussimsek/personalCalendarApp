import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/db/database.dart';
import '../../data/sync/mappers.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'note_editor_screen.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => NotesScreenState();
}

class NotesScreenState extends ConsumerState<NotesScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  List<Note>? _results;
  Timer? _debounce;

  void focusSearch() => _searchFocus.requestFocus();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final r = await ref.read(noteRepositoryProvider).search(q);
      if (mounted) setState(() => _results = r);
    });
  }

  void _open(Note? n) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: n?.id)));

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final all = ref.watch(notesProvider).value ?? const <Note>[];
    final notes = _results ?? all;
    // keep search results fresh when notes change
    ref.listen(notesProvider, (_, _) {
      if (_search.text.trim().isNotEmpty) _onQuery(_search.text);
    });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: _search,
            focusNode: _searchFocus,
            hintText: l.searchNotes,
            leading: const Icon(Icons.search),
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      _onQuery('');
                    }),
            ],
            onChanged: _onQuery,
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? Center(child: Text(l.noNotes, style: TextStyle(color: Theme.of(context).colorScheme.outline)))
              : ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, i) {
                    final n = notes[i];
                    final tags = noteTags(n);
                    final preview = n.body.replaceAll(RegExp(r'[#*_>`\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
                    return ListTile(
                      leading: Icon(n.pinned ? Icons.push_pin : Icons.notes_outlined, size: 20),
                      title: Text(n.title.isEmpty ? l.untitled : n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [if (preview.isNotEmpty) preview, if (tags.isNotEmpty) tags.map((t) => '#$t').join(' ')].join('  ·  '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(Dates.dayShort.format(n.updatedAt.toLocal()), style: Theme.of(context).textTheme.labelSmall),
                      onTap: () => _open(n),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

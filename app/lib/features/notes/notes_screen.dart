import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/db/database.dart';
import '../../data/sync/mappers.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../home/shell_actions.dart';
import 'note_editor_screen.dart';

const _recentSearchesKey = 'notes.recent_searches';

/// Notes: search with suggestions, tag filter, pinned cards, recent list.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => NotesScreenState();
}

class NotesScreenState extends ConsumerState<NotesScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  List<Note>? _results;
  String? _tag;
  List<String> _recent = const [];
  Timer? _debounce;

  void focusSearch() => _searchFocus.requestFocus();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
    _loadRecent();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final raw = await ref.read(databaseProvider).getState(_recentSearchesKey);
    if (raw != null && mounted) setState(() => _recent = (jsonDecode(raw) as List<dynamic>).cast<String>());
  }

  Future<void> _remember(String q) async {
    q = q.trim();
    if (q.length < 2) return;
    final next = [q, ..._recent.where((r) => r != q)].take(5).toList();
    setState(() => _recent = next);
    await ref.read(databaseProvider).setState(_recentSearchesKey, jsonEncode(next));
  }

  Future<void> _forget(String q) async {
    final next = _recent.where((r) => r != q).toList();
    setState(() => _recent = next);
    await ref.read(databaseProvider).setState(_recentSearchesKey, jsonEncode(next));
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

  void _setQuery(String q) {
    _search.text = q;
    _search.selection = TextSelection.collapsed(offset: q.length);
    _onQuery(q);
  }

  void _open(Note? n) {
    if (_search.text.trim().isNotEmpty) _remember(_search.text);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: n?.id)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final all = ref.watch(notesProvider).value ?? const <Note>[];
    ref.listen(notesProvider, (_, _) {
      if (_search.text.trim().isNotEmpty) _onQuery(_search.text);
    });

    // tag frequencies
    final tagCounts = <String, int>{};
    for (final n in all) {
      for (final tag in noteTags(n)) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }
    final tags = tagCounts.keys.toList()..sort((a, b) => tagCounts[b]!.compareTo(tagCounts[a]!));

    final searching = _search.text.trim().isNotEmpty;
    final showSuggestions = _searchFocus.hasFocus && !searching;
    var notes = _results ?? all;
    if (_tag != null) notes = notes.where((n) => noteTags(n).contains(_tag)).toList();
    final pinned = searching ? const <Note>[] : notes.where((n) => n.pinned).toList();
    final rest = searching ? notes : notes.where((n) => !n.pinned).toList();

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Row(children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.lg), boxShadow: _searchFocus.hasFocus ? null : t.shadow),
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (q) {
                _onQuery(q);
                setState(() {});
              },
              onSubmitted: _remember,
              decoration: InputDecoration(
                hintText: l.searchNotes,
                fillColor: t.surface,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searching
                    ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _setQuery(''))
                    : null,
              ),
            ),
          ),
        ),
        if (_searchFocus.hasFocus)
          TextButton(
            onPressed: () {
              _setQuery('');
              _searchFocus.unfocus();
            },
            child: Text(l.cancel),
          ),
      ]),
    );

    Widget body;
    if (showSuggestions) {
      body = _Suggestions(
        recent: _recent,
        tags: tags,
        tagCounts: tagCounts,
        onRecent: _setQuery,
        onForget: _forget,
        onTag: (tag) {
          _searchFocus.unfocus();
          setState(() => _tag = tag);
        },
        onOpen: _open,
      );
    } else if (all.isEmpty) {
      body = EmptyState(
        icon: Icons.sticky_note_2_outlined,
        title: l.emptyNotesTitle,
        message: l.emptyNotesBody,
        examples: [l.exampleNote1],
        onExample: (e) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(initialTitle: e))),
      );
    } else if (notes.isEmpty) {
      body = EmptyState(icon: Icons.search_off_rounded, title: l.noResults, message: _search.text);
    } else {
      body = ListView(padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg), children: [
        if (pinned.isNotEmpty) ...[
          SectionHeader(l.pinnedSection, icon: Icons.push_pin_outlined, small: true),
          for (final n in pinned)
            Padding(padding: const EdgeInsets.only(bottom: Space.md), child: _PinnedCard(n, onTap: () => _open(n))),
          const SizedBox(height: Space.md),
        ],
        if (rest.isNotEmpty) ...[
          if (!searching) SectionHeader(l.recentNotes, small: true),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            radius: Radii.lg,
            child: Column(children: [
              for (var i = 0; i < rest.length; i++) ...[
                if (i > 0) const Divider(),
                _NoteRow(rest[i], onTap: () => _open(rest[i])),
              ],
            ]),
          ),
        ],
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(title: l.tabNotes, trailing: const ShellActions()),
      searchField,
      if (!showSuggestions && tags.isNotEmpty)
        SizedBox(
          height: 32,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            scrollDirection: Axis.horizontal,
            itemCount: tags.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
            itemBuilder: (_, i) => Pill(
              label: '#${tags[i]}',
              neutral: _tag != tags[i],
              onTap: () => setState(() => _tag = _tag == tags[i] ? null : tags[i]),
            ),
          ),
        ),
      if (!showSuggestions && tags.isNotEmpty) const SizedBox(height: Space.lg),
      Expanded(child: body),
    ]);
  }
}

String _preview(Note n) => n.body.replaceAll(RegExp(r'[#*_>`\-\[\]]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _when(DateTime d) {
  final l = d.toLocal();
  final now = DateTime.now();
  if (Dates.sameDay(l, now)) return Dates.time.format(l);
  if (now.difference(l).inDays < 7) return Dates.weekdayShort.format(l);
  return Dates.dayMonthShort.format(l);
}

class _PinnedCard extends ConsumerWidget {
  const _PinnedCard(this.note, {required this.onTap});
  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final t = context.tokens;
    final tags = noteTags(note);
    final preview = _preview(note);
    return AppCard(
      onTap: onTap,
      radius: Radii.lg,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(note.title.isEmpty ? l.untitled : note.title, style: context.text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
        ],
        const SizedBox(height: Space.md),
        Row(children: [
          for (final tag in tags.take(2)) ...[
            Text('#$tag', style: context.text.labelMedium?.copyWith(color: t.accent)),
            const SizedBox(width: Space.md),
          ],
          if (note.eventId != null) Icon(Icons.event_outlined, size: 16, color: t.secondary),
          const Spacer(),
          Text(_when(note.updatedAt), style: context.text.bodySmall),
        ]),
      ]),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow(this.note, {required this.onTap});
  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = context.tokens;
    final tags = noteTags(note);
    final preview = _preview(note);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(note.title.isEmpty ? l.untitled : note.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
            ),
            const SizedBox(width: Space.sm),
            Text(_when(note.updatedAt), style: context.text.bodySmall?.copyWith(fontFeatures: tabularFigures)),
          ]),
          if (preview.isNotEmpty || tags.isNotEmpty)
            Text.rich(
              TextSpan(children: [
                TextSpan(text: preview),
                if (tags.isNotEmpty) TextSpan(text: '${preview.isEmpty ? '' : ' · '}#${tags.first}', style: TextStyle(color: t.accent, fontWeight: FontWeight.w600)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
        ]),
      ),
    );
  }
}

/// Shown when the search box is focused but empty — never a blank screen.
class _Suggestions extends ConsumerWidget {
  const _Suggestions({
    required this.recent,
    required this.tags,
    required this.tagCounts,
    required this.onRecent,
    required this.onForget,
    required this.onTag,
    required this.onOpen,
  });
  final List<String> recent;
  final List<String> tags;
  final Map<String, int> tagCounts;
  final ValueChanged<String> onRecent;
  final ValueChanged<String> onForget;
  final ValueChanged<String> onTag;
  final ValueChanged<Note> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L10n.of(context);
    final t = context.tokens;
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    final linked = notes.where((n) => n.eventId != null).take(3).toList();
    return ListView(padding: const EdgeInsets.symmetric(horizontal: Space.lg), children: [
      if (recent.isNotEmpty) ...[
        SectionHeader(l.recentSearches, small: true),
        for (final r in recent)
          InkWell(
            onTap: () => onRecent(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Row(children: [
                Icon(Icons.history_rounded, size: 20, color: t.faint),
                const SizedBox(width: Space.md),
                Expanded(child: Text(r, style: context.text.bodyLarge)),
                IconButton(icon: Icon(Icons.close_rounded, size: 16, color: t.faint), onPressed: () => onForget(r)),
              ]),
            ),
          ),
        const SizedBox(height: Space.xl),
      ],
      if (tags.isNotEmpty) ...[
        SectionHeader(l.tagsSection, small: true),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final tag in tags.take(12)) Pill(neutral: true, label: '#$tag · ${tagCounts[tag]}', onTap: () => onTag(tag)),
        ]),
        const SizedBox(height: Space.xl),
      ],
      if (linked.isNotEmpty) ...[
        SectionHeader(l.linkedThisWeek, small: true),
        for (final n in linked)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: AppCard.tight(
              onTap: () => onOpen(n),
              child: Row(children: [
                Icon(Icons.sticky_note_2_outlined, color: t.accent),
                const SizedBox(width: Space.md),
                Expanded(child: Text(n.title.isEmpty ? l.untitled : n.title, style: context.text.titleSmall)),
              ]),
            ),
          ),
      ],
    ]);
  }
}

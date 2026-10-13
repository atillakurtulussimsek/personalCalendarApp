import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../calendar/calendar_screen.dart';
import '../notes/note_editor_screen.dart';
import '../notes/notes_screen.dart';
import 'sync_indicator.dart';

/// Root scaffold: bottom navigation on Android, navigation rail on macOS.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  final _calendarKey = GlobalKey<CalendarScreenState>();
  final _notesKey = GlobalKey<NotesScreenState>();

  @override
  void initState() {
    super.initState();
    ref.read(syncTriggersProvider).start();
  }

  void _newItem() {
    if (_index == 0) {
      _calendarKey.currentState?.createEvent();
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NoteEditorScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final wide = Platform.isMacOS || MediaQuery.sizeOf(context).width >= 700;
    final pages = [
      CalendarScreen(key: _calendarKey),
      NotesScreen(key: _notesKey),
    ];
    final destinations = [
      (Icons.calendar_month_outlined, Icons.calendar_month, l.tabCalendar),
      (Icons.notes_outlined, Icons.notes, l.tabNotes),
    ];

    final body = Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? l.tabCalendar : l.tabNotes),
        actions: [
          const SyncIndicator(),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') ref.read(sessionProvider.notifier).logout();
            },
            itemBuilder: (_) => [PopupMenuItem(value: 'logout', child: Text(l.logout))],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: FloatingActionButton(
        tooltip: _index == 0 ? l.newEvent : l.newNote,
        onPressed: _newItem,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
    );

    final shell = !wide
        ? body
        : Row(children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]);

    // Desktop keyboard shortcuts: ⌘N new, ⌘F search, ⌘1/⌘2 tabs.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newItem,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newItem,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          setState(() => _index = 1);
          _notesKey.currentState?.focusSearch();
        },
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => setState(() => _index = 0),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => setState(() => _index = 1),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () => ref.read(syncServiceProvider).sync(),
      },
      child: Focus(autofocus: true, child: shell),
    );
  }
}

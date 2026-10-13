import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/recurrence.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/app_intents.dart';
import '../../platform/desktop_integration.dart';
import '../calendar/event_editor_screen.dart';
import '../capture/capture_sheet.dart';
import '../settings/settings_screen.dart';
import '../../providers.dart';
import '../calendar/calendar_screen.dart';
import '../calendar/calendars_screen.dart';
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

  StreamSubscription<AppIntent>? _intents;

  @override
  void initState() {
    super.initState();
    ref.read(syncTriggersProvider).start();
    ref.read(widgetPublisherProvider).start();
    _intents = AppIntents.instance.stream.listen(_onIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final l = L10n.of(context);
      await AppIntents.instance.start(shortcutTitles: {
        AppIntentType.capture: l.shortcutCapture,
        AppIntentType.newNote: l.shortcutNewNote,
        AppIntentType.newEvent: l.shortcutNewEvent,
        AppIntentType.today: l.shortcutToday,
      });
      AppIntents.instance.flush();
      await _startDesktop();
      await _maybeAskPermissions();
    });
  }

  Future<void> _startDesktop() async {
    if (!DesktopIntegration.supported) return;
    final d = ref.read(desktopIntegrationProvider);
    await d.start();
    final db = ref.read(databaseProvider);
    final hk = await db.getState(SettingKeys.hotkey);
    await d.setHotKey(hk == null ? DesktopIntegration.defaultHotKey() : DesktopIntegration.decodeHotKey(hk));
    if ((await db.getState(SettingKeys.hideDock)) == 'true') await d.setHideDock(true);
  }

  @override
  void dispose() {
    _intents?.cancel();
    super.dispose();
  }

  bool _capturing = false;

  Future<void> _capture([String? text]) async {
    if (_capturing) return;
    _capturing = true;
    try {
      await showCaptureSheet(context, initialText: text);
    } finally {
      _capturing = false;
    }
  }

  void _onIntent(AppIntent i) {
    if (!mounted) return;
    switch (i.type) {
      case AppIntentType.capture:
        _capture(i.text);
      case AppIntentType.newNote:
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(initialBody: i.text)));
      case AppIntentType.newEvent:
        openEventEditor(context);
      case AppIntentType.today:
        setState(() => _index = 0);
        _calendarKey.currentState?.goToday();
      case AppIntentType.openEvent:
        _openEventById(i.text);
      case AppIntentType.show:
        break;
    }
  }

  Future<void> _openEventById(String? id) async {
    if (id == null) return;
    final e = await ref.read(eventRepositoryProvider).get(id);
    if (e == null || !mounted) return;
    // a master or a single event: show the next occurrence from now, else the event itself
    final occs = expandEvents([e], DateTime.now(), DateTime.now().add(const Duration(days: 400)));
    final occ = occs.isNotEmpty ? occs.first : Occurrence(event: e, start: e.startAt, end: e.endAt, seriesId: e.recurrenceId ?? e.id, isException: e.recurrenceId != null);
    if (mounted) await openEventEditor(context, occurrence: occ);
  }

  /// First launch: explain and request notification / exact-alarm permissions.
  Future<void> _maybeAskPermissions() async {
    final db = ref.read(databaseProvider);
    if (await db.getState(SettingKeys.permissionsAsked) == 'true') return;
    await db.setState(SettingKeys.permissionsAsked, 'true');
    if (!mounted || !(Platform.isAndroid || Platform.isMacOS)) return;
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.permissionDialogTitle),
        content: Text(l.permissionDialogBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.permissionDialogLater)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.permissionDialogAllow)),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(remindersServiceProvider).requestPermissions();
      await ref.read(remindersServiceProvider).refresh();
    }
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
          IconButton(tooltip: '${l.quickCapture} (⌘K)', icon: const Icon(Icons.bolt), onPressed: () => _capture()),
          const SyncIndicator(),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') ref.read(sessionProvider.notifier).logout();
              if (v == 'calendars') Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CalendarsScreen()));
              if (v == 'settings') Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'calendars', child: Text(l.calendars)),
              PopupMenuItem(value: 'settings', child: Text(l.settings)),
              PopupMenuItem(value: 'logout', child: Text(l.logout)),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: GestureDetector(
        onLongPress: () => _capture(),
        child: FloatingActionButton(
          tooltip: _index == 0 ? l.newEvent : l.newNote,
          onPressed: _newItem,
          child: const Icon(Icons.add),
        ),
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
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _capture(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _capture(),
      },
      child: Focus(autofocus: true, child: shell),
    );
  }
}

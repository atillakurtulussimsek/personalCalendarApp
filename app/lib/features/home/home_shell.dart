import 'dart:async';

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
import '../tasks/tasks_screen.dart';
import '../../providers.dart';
import '../calendar/calendar_screen.dart';
import '../notes/note_editor_screen.dart';
import '../notes/notes_screen.dart';
import '../../core/ui.dart';
import '../today/today_screen.dart';
import '../../core/platform_info.dart';

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
  final _tasksKey = GlobalKey<TasksScreenState>();

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

  static const _today = 0, _calendar = 1, _notes = 2, _tasks = 3;

  /// Opens quick capture with the target and day that fit the current tab.
  Future<void> _capture([String? text]) async {
    if (_capturing) return;
    _capturing = true;
    try {
      await showCaptureSheet(
        context,
        initialText: text,
        target: switch (_index) {
          _notes => CaptureTarget.note,
          _tasks => CaptureTarget.task,
          _ => CaptureTarget.auto,
        },
        baseDay: _index == _calendar ? _calendarKey.currentState?.selectedDay : null,
      );
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
        setState(() => _index = _today);
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
    if (!mounted || !(PlatformInfo.isAndroid || PlatformInfo.isMacOS)) return;
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
    switch (_index) {
      case _notes:
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NoteEditorScreen()));
      case _tasks:
        _tasksKey.currentState?.createTask();
      default:
        _calendarKey.currentState?.createEvent();
    }
  }

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final wide = PlatformInfo.isDesktop || MediaQuery.sizeOf(context).width >= 700;
    final pages = [
      const TodayScreen(),
      CalendarScreen(key: _calendarKey),
      NotesScreen(key: _notesKey),
      TasksScreen(key: _tasksKey),
    ];
    final destinations = [
      (Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, l.tabToday),
      (Icons.calendar_today_outlined, Icons.calendar_today_rounded, l.tabCalendar),
      (Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded, l.tabNotes),
      (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, l.tabTasks),
    ];
    final hint = [l.captureHintToday, l.captureHintCalendar, l.captureHintNotes, l.captureHintTasks][_index];

    final content = Column(children: [
      Expanded(child: SafeArea(bottom: false, child: IndexedStack(index: _index, children: pages))),
      CaptureBar(hint: hint, onTap: () => _capture()),
    ]);

    final Widget shell = wide
        ? Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.9,
                destinations: [
                  for (final d in destinations) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: SafeArea(child: content)),
            ]),
          )
        : Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: [
                for (final d in destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
          );

    // Desktop shortcuts: ⌘N new, ⌘K capture, ⌘F search, ⌘1–4 tabs, ⌘R sync.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newItem,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newItem,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          _select(_notes);
          _notesKey.currentState?.focusSearch();
        },
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => _select(_today),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => _select(_calendar),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => _select(_notes),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => _select(_tasks),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () => ref.read(syncServiceProvider).sync(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _capture(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _capture(),
      },
      child: Focus(autofocus: true, child: shell),
    );
  }
}

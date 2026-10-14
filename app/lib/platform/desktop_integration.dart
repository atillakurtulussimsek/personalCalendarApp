import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import '../core/dates.dart';
import '../core/recurrence.dart';
import '../data/repositories/repositories.dart';
import 'app_intents.dart';
import '../core/platform_info.dart';

// ignore_for_file: deprecated_member_use

/// macOS: menu bar icon with upcoming events + quick capture, global hotkey,
/// hide-to-tray on close, Dock hiding and launch-at-login.
class DesktopIntegration with TrayListener, WindowListener {
  DesktopIntegration(this.events, this.calendars, this.labels);

  final EventRepository events;
  final CalendarRepository calendars;
  final DesktopLabels labels;

  static const _macos = MethodChannel('personal_calendar/macos');
  static bool get supported => PlatformInfo.isMacOS;

  StreamSubscription<List<Occurrence>>? _sub;
  HotKey? _hotKey;
  bool _started = false;

  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
      await trayManager.setToolTip(labels.appTitle);
    } catch (_) {}
    _sub = events.watchOccurrences(DateTime.now(), DateTime.now().add(const Duration(days: 7))).listen((occ) async {
      final cals = {for (final c in await calendars.watchAll().first) c.id: c};
      await _rebuildMenu(occ.where((o) => (cals[o.calendarId]?.visible ?? true) && o.end.isAfter(DateTime.now())).take(6).toList());
    });
  }

  Future<void> _rebuildMenu(List<Occurrence> upcoming) async {
    final items = <MenuItem>[
      MenuItem(key: 'capture', label: '${labels.quickCapture}…'),
      MenuItem.separator(),
      if (upcoming.isEmpty) MenuItem(key: 'none', label: labels.noEvents, disabled: true),
      for (final o in upcoming)
        MenuItem(
          key: 'ev:${o.event.id}',
          label: '${o.allDay ? Dates.dayShort.format(o.start.toLocal()) : Dates.dateTime.format(o.start.toLocal())}  ${o.title}',
        ),
      MenuItem.separator(),
      MenuItem(key: 'show', label: labels.showWindow),
      MenuItem(key: 'quit', label: labels.quit),
    ];
    try {
      await trayManager.setContextMenu(Menu(items: items));
    } catch (_) {}
  }

  @override
  void onTrayIconMouseUp() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'capture':
        showAndCapture();
      case 'show':
        showWindow();
      case 'quit':
        windowManager.setPreventClose(false).then((_) => windowManager.close());
      default:
        if (menuItem.key?.startsWith('ev:') ?? false) showWindow();
    }
  }

  @override
  void onWindowClose() async {
    // closing hides to the menu bar; Quit from the tray exits
    if (await windowManager.isPreventClose()) await windowManager.hide();
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
    AppIntents.instance.emit(const AppIntent(AppIntentType.show));
  }

  Future<void> showAndCapture() async {
    await windowManager.show();
    await windowManager.focus();
    AppIntents.instance.emit(const AppIntent(AppIntentType.capture));
  }

  // --- settings ------------------------------------------------------------

  /// Registers the system-wide hotkey; null removes it.
  Future<void> setHotKey(HotKey? hk) async {
    if (!supported) return;
    if (_hotKey != null) {
      try {
        await hotKeyManager.unregister(_hotKey!);
      } catch (_) {}
    }
    _hotKey = hk;
    if (hk == null) return;
    try {
      await hotKeyManager.register(hk, keyDownHandler: (_) => showAndCapture());
    } catch (_) {}
  }

  static HotKey defaultHotKey() => HotKey(key: PhysicalKeyboardKey.space, modifiers: [HotKeyModifier.alt], scope: HotKeyScope.system);

  static String encodeHotKey(HotKey hk) => jsonEncode(hk.toJson());
  static HotKey? decodeHotKey(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return HotKey.fromJson((jsonDecode(s) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> setHideDock(bool hide) async {
    if (!supported) return;
    try {
      await windowManager.setSkipTaskbar(hide);
    } catch (_) {}
  }

  Future<void> setLaunchAtLogin(bool enabled) async {
    if (!supported) return;
    try {
      await _macos.invokeMethod('setLaunchAtLogin', {'enabled': enabled});
    } on MissingPluginException {
      // no native bridge on this platform
    }
  }

  Future<bool> isLaunchAtLogin() async {
    if (!supported) return false;
    try {
      return await _macos.invokeMethod<bool>('isLaunchAtLogin') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    if (_hotKey != null) await hotKeyManager.unregister(_hotKey!);
  }
}

class DesktopLabels {
  const DesktopLabels({required this.appTitle, required this.quickCapture, required this.noEvents, required this.showWindow, required this.quit});
  final String appTitle;
  final String quickCapture;
  final String noEvents;
  final String showWindow;
  final String quit;
}

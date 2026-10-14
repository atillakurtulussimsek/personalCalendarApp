import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/ics.dart';
import '../../data/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/app_intents.dart';
import '../../platform/desktop_integration.dart';
import '../../platform/live_sync.dart';
import '../../providers.dart';
import '../../core/platform_info.dart';

/// Keys in the sync_state kv table used for device-local settings.
class SettingKeys {
  static const captureNotification = 'setting.capture_notification';
  static const hotkey = 'setting.hotkey';
  static const hideDock = 'setting.hide_dock';
  static const launchAtLogin = 'setting.launch_at_login';
  static const permissionsAsked = 'setting.permissions_asked';
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _captureNotification = false;
  bool _hideDock = false;
  bool _launchAtLogin = false;
  HotKey? _hotKey;
  String _email = '';
  String _server = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final auth = ref.read(authRepositoryProvider);
    _captureNotification = (await db.getState(SettingKeys.captureNotification)) == 'true';
    _hideDock = (await db.getState(SettingKeys.hideDock)) == 'true';
    _launchAtLogin = (await db.getState(SettingKeys.launchAtLogin)) == 'true';
    final hk = await db.getState(SettingKeys.hotkey);
    _hotKey = hk == null ? DesktopIntegration.defaultHotKey() : DesktopIntegration.decodeHotKey(hk);
    _email = await auth.email ?? '';
    _server = await auth.serverUrl;
    if (mounted) setState(() {});
  }

  Future<void> _set(String key, String value) => ref.read(databaseProvider).setState(key, value);

  Future<void> _importIcs() async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final calendars = (ref.read(calendarsProvider).value ?? const <Calendar>[]).where((c) => c.source == 'local').toList();
    if (calendars.isEmpty) return;
    final calId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.chooseCalendar),
        children: [for (final c in calendars) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c.id), child: Text(c.name))],
      ),
    );
    if (calId == null) return;
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ics']);
      if (picked.isEmpty) return;
      final text = await picked.single.xFile.readAsString();
      final n = await ref.read(calendarRepositoryProvider).importIcs(calId, text);
      messenger.showSnackBar(SnackBar(content: Text(l.importDone(n))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.importFailed(e.toString()))));
    }
  }

  Future<void> _exportIcs() async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final cals = {for (final c in await db.select(db.calendars).get()) c.id: c};
    final rows = await (db.select(db.events)..where((t) => t.deletedAt.isNull())).get();
    final events = rows.where((e) => cals[e.calendarId]?.source == 'local' && e.recurrenceId == null).map((e) => IcsEvent(
          uid: e.id,
          summary: e.title,
          description: e.description,
          location: e.location,
          start: e.startAt,
          end: e.endAt,
          allDay: e.allDay,
          rrule: e.rrule,
          timezone: e.timezone,
        ));
    final text = writeIcs(events);
    try {
      final uri = await FilePicker.saveFile(
          fileName: 'takvim.ics', bytes: Uint8List.fromList(utf8.encode(text)), mimeType: 'text/calendar', type: FileType.custom, allowedExtensions: ['ics']);
      if (uri != null) messenger.showSnackBar(SnackBar(content: Text(l.exportDone(uri.path))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.importFailed(e.toString()))));
    }
  }

  Future<void> _recordHotKey() async {
    final l = L10n.of(context);
    final hk = await showDialog<HotKey?>(
      context: context,
      builder: (ctx) => _HotKeyRecorderDialog(title: l.hotkeyPressKeys, clearLabel: l.hotkeyClear, cancelLabel: l.cancel),
    );
    if (!mounted) return;
    setState(() => _hotKey = hk);
    await _set(SettingKeys.hotkey, hk == null ? '' : DesktopIntegration.encodeHotKey(hk));
    await ref.read(desktopIntegrationProvider).setHotKey(hk);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        children: [
          ListTile(leading: const Icon(Icons.person_outline), title: Text(l.settingsAccount), subtitle: Text(_email)),
          if (!PlatformInfo.isWeb) ListTile(leading: const Icon(Icons.dns_outlined), title: Text(l.settingsServer), subtitle: Text(_server)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l.settingsAppearance),
            trailing: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem)),
                ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark)),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(l.importIcs),
            subtitle: Text(l.importIcsHint),
            onTap: _importIcs,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l.exportIcs),
            onTap: _exportIcs,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l.settingsNotificationPermission),
            subtitle: Text(l.settingsNotificationPermissionHint),
            onTap: () async {
              await ref.read(remindersServiceProvider).requestPermissions(exact: false);
              await ref.read(remindersServiceProvider).refresh();
              if (mounted) setState(() {});
            },
          ),
          if (PlatformInfo.isAndroid) ...[
            ListTile(
              leading: Icon(ref.read(remindersServiceProvider).exactAllowed ? Icons.alarm_on : Icons.alarm_off),
              title: Text(l.settingsExactAlarm),
              subtitle: Text(ref.read(remindersServiceProvider).exactAllowed ? l.settingsExactAlarmHintOn : l.settingsExactAlarmHintOff),
              onTap: () async {
                await ref.read(remindersServiceProvider).requestPermissions(exact: true);
                await ref.read(remindersServiceProvider).refresh();
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: Text(l.settingsBatteryHint),
              dense: true,
            ),
          ],
          ListTile(
            leading: Icon(ref.watch(liveStateProvider).value == LiveState.connected ? Icons.bolt : Icons.bolt_outlined),
            title: Text(l.settingsLiveSync),
            subtitle: Text(
                '${l.settingsLiveSyncHint} · ${ref.watch(liveStateProvider).value == LiveState.connected ? l.liveStatusConnected : l.liveStatusDisconnected}'),
          ),
          const Divider(),
          if (PlatformInfo.isAndroid)
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(l.settingsCaptureNotification),
              subtitle: Text(l.settingsCaptureNotificationHint),
              value: _captureNotification,
              onChanged: (v) async {
                setState(() => _captureNotification = v);
                await _set(SettingKeys.captureNotification, '$v');
                await AppIntents.instance.setCaptureNotification(v);
              },
            ),
          if (PlatformInfo.isMacOS) ...[
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(l.settingsHotkey),
              subtitle: Text(l.settingsHotkeyHint),
              trailing: Text(_hotKey == null ? '—' : _describe(_hotKey!)),
              onTap: _recordHotKey,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dock_outlined),
              title: Text(l.settingsHideDock),
              value: _hideDock,
              onChanged: (v) async {
                setState(() => _hideDock = v);
                await _set(SettingKeys.hideDock, '$v');
                await ref.read(desktopIntegrationProvider).setHideDock(v);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.login_outlined),
              title: Text(l.settingsLaunchAtLogin),
              value: _launchAtLogin,
              onChanged: (v) async {
                setState(() => _launchAtLogin = v);
                await _set(SettingKeys.launchAtLogin, '$v');
                await ref.read(desktopIntegrationProvider).setLaunchAtLogin(v);
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.logout),
            onTap: () {
              Navigator.of(context).pop();
              ref.read(sessionProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }

  static String _describe(HotKey hk) {
    final mods = (hk.modifiers ?? const <HotKeyModifier>[]).map((m) => switch (m) {
          HotKeyModifier.alt => '⌥',
          HotKeyModifier.control => '⌃',
          HotKeyModifier.shift => '⇧',
          HotKeyModifier.meta => '⌘',
          HotKeyModifier.capsLock => '⇪',
          HotKeyModifier.fn => 'fn',
        });
    final key = hk.logicalKey.keyLabel.isEmpty ? hk.logicalKey.debugName ?? '?' : hk.logicalKey.keyLabel;
    return '${mods.join()}${key == ' ' ? 'Space' : key}';
  }
}

/// Records the next key combination pressed.
class _HotKeyRecorderDialog extends StatefulWidget {
  const _HotKeyRecorderDialog({required this.title, required this.clearLabel, required this.cancelLabel});
  final String title;
  final String clearLabel;
  final String cancelLabel;

  @override
  State<_HotKeyRecorderDialog> createState() => _HotKeyRecorderDialogState();
}

class _HotKeyRecorderDialogState extends State<_HotKeyRecorderDialog> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.physicalKey;
    final modifierKeys = {
      PhysicalKeyboardKey.altLeft, PhysicalKeyboardKey.altRight, PhysicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlRight,
      PhysicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftRight, PhysicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaRight,
    };
    if (modifierKeys.contains(key)) return KeyEventResult.handled;
    final pressed = HardwareKeyboard.instance;
    final mods = <HotKeyModifier>[
      if (pressed.isAltPressed) HotKeyModifier.alt,
      if (pressed.isControlPressed) HotKeyModifier.control,
      if (pressed.isShiftPressed) HotKeyModifier.shift,
      if (pressed.isMetaPressed) HotKeyModifier.meta,
    ];
    if (mods.isEmpty) return KeyEventResult.handled; // a bare key would hijack typing everywhere
    Navigator.of(context).pop(HotKey(key: key, modifiers: mods, scope: HotKeyScope.system));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: const SizedBox(height: 48, child: Center(child: Icon(Icons.keyboard, size: 32))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text(widget.clearLabel)),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.cancelLabel)),
      ],
    );
  }
}

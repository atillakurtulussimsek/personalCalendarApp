import 'dart:async';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';
import '../core/platform_info.dart';

/// Something outside the UI asked the app to do: share sheet, widget,
/// Quick Settings tile, notification action, app shortcut, tray, hotkey, URL.
enum AppIntentType { capture, newNote, newEvent, today, show, openEvent }

class AppIntent {
  const AppIntent(this.type, {this.text});
  final AppIntentType type;
  final String? text;

  /// personalcalendar://capture?text=… | note | event | today | show
  static AppIntent? fromUri(Uri? uri) {
    if (uri == null) return null;
    final host = (uri.host.isEmpty ? uri.path : uri.host).replaceAll('/', '');
    final text = uri.queryParameters['text'];
    return switch (host) {
      'capture' => AppIntent(AppIntentType.capture, text: text),
      'note' => AppIntent(AppIntentType.newNote, text: text),
      'event' => AppIntent(AppIntentType.newEvent, text: text),
      'today' => const AppIntent(AppIntentType.today),
      'show' => const AppIntent(AppIntentType.show),
      _ => null,
    };
  }
}

/// Collects intents from every native entry point into one stream.
class AppIntents {
  AppIntents._();
  static final AppIntents instance = AppIntents._();

  static const _channel = MethodChannel('personal_calendar/intents');
  final _controller = StreamController<AppIntent>.broadcast();
  final _pending = <AppIntent>[];
  bool _started = false;

  Stream<AppIntent> get stream => _controller.stream;

  /// Emits an intent; buffered until a listener is attached.
  void emit(AppIntent intent) {
    if (_controller.hasListener) {
      _controller.add(intent);
    } else {
      _pending.add(intent);
    }
  }

  /// Delivers intents that arrived before the UI was ready.
  void flush() {
    for (final p in _pending) {
      _controller.add(p);
    }
    _pending.clear();
  }

  Future<void> start({required Map<AppIntentType, String> shortcutTitles}) async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'intent') {
        final args = (call.arguments as Map).cast<String, dynamic>();
        final uri = Uri.tryParse(args['uri'] as String? ?? '');
        final text = args['text'] as String?;
        final intent = AppIntent.fromUri(uri) ?? (text != null ? AppIntent(AppIntentType.capture, text: text) : null);
        if (intent != null) emit(intent);
      }
    });
    // whatever launched us (share sheet, tile, notification, URL) before Dart was up
    try {
      final initial = await _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialIntent');
      if (initial != null) {
        final uri = Uri.tryParse(initial['uri'] as String? ?? '');
        final text = initial['text'] as String?;
        final intent = AppIntent.fromUri(uri) ?? (text != null ? AppIntent(AppIntentType.capture, text: text) : null);
        if (intent != null) emit(intent);
      }
    } on MissingPluginException {
      // platform without the native bridge (tests)
    }

    if (PlatformInfo.isAndroid) {
      // home screen widget taps
      try {
        final launch = await HomeWidget.initiallyLaunchedFromHomeWidget();
        final i = AppIntent.fromUri(launch);
        if (i != null) emit(i);
        HomeWidget.widgetClicked.listen((uri) {
          final i = AppIntent.fromUri(uri);
          if (i != null) emit(i);
        });
      } catch (_) {}
      // long-press app shortcuts
      try {
        const qa = QuickActions();
        await qa.initialize((type) {
          final t = AppIntentType.values.firstWhere((v) => v.name == type, orElse: () => AppIntentType.show);
          emit(AppIntent(t));
        });
        await qa.setShortcutItems([
          ShortcutItem(type: AppIntentType.capture.name, localizedTitle: shortcutTitles[AppIntentType.capture]!, icon: 'ic_shortcut_bolt'),
          ShortcutItem(type: AppIntentType.newNote.name, localizedTitle: shortcutTitles[AppIntentType.newNote]!, icon: 'ic_shortcut_note'),
          ShortcutItem(type: AppIntentType.newEvent.name, localizedTitle: shortcutTitles[AppIntentType.newEvent]!, icon: 'ic_shortcut_event'),
          ShortcutItem(type: AppIntentType.today.name, localizedTitle: shortcutTitles[AppIntentType.today]!, icon: 'ic_shortcut_today'),
        ]);
      } catch (_) {}
    }
  }

  /// Android: toggles the persistent "quick note" notification.
  Future<void> setCaptureNotification(bool enabled) async {
    if (!PlatformInfo.isAndroid) return;
    try {
      await _channel.invokeMethod('setCaptureNotification', {'enabled': enabled});
    } on MissingPluginException {
      // no native bridge on this platform
    }
  }
}

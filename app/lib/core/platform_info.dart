import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform checks that are safe on the web (where `Platform` throws).
class PlatformInfo {
  PlatformInfo._();
  static bool get isWeb => kIsWeb;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isDesktop => isMacOS;

  /// Value sent to the server as device platform.
  static String get name => isAndroid ? 'android' : (isMacOS ? 'macos' : (kIsWeb ? 'web' : 'other'));
}

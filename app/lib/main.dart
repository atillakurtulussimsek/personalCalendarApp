
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/tz.dart';
import 'platform/push_service.dart';

Future<void> main() async {
  // surface errors with their stack instead of a bare "Uncaught Error" (web)
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('uncaught: $e\n$st');
    return true;
  };
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'tr_TR';
  await initializeDateFormatting('tr');
  await Tz.init();
  await PushService.initFirebase();
  runApp(const ProviderScope(child: App()));
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'l10n/app_localizations.dart';
import 'providers.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      onGenerateTitle: (ctx) => L10n.of(ctx).appTitle,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('tr'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: switch (session) {
        SessionState.unknown => const Scaffold(body: Center(child: CircularProgressIndicator())),
        SessionState.loggedOut => const LoginScreen(),
        SessionState.loggedIn => const HomeShell(),
      },
    );
  }
}

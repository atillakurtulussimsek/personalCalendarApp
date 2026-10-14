import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/data/api/token_store.dart';
import 'package:personal_calendar/features/auth/login_screen.dart';
import 'package:personal_calendar/l10n/app_localizations.dart';
import 'package:personal_calendar/providers.dart';

void main() {
  testWidgets('login form validates input before calling the server', (tester) async {
    // phone-sized surface (390×844 logical)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(MemoryTokenStore())],
      child: const MaterialApp(
        locale: Locale('tr'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: [L10n.delegate, ...GlobalMaterialLocalizations.delegates],
        home: LoginScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Giriş yap'), findsOneWidget);
    // fresh install on a native platform: server, email, password
    await tester.enterText(find.byType(TextFormField).at(1), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(2), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('Geçerli bir e-posta gir'), findsOneWidget);
    expect(find.text('Parola en az 8 karakter olmalı'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Hesap oluştur'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Kayıt ol'), findsOneWidget);
    expect(find.text('Zaten hesabım var'), findsOneWidget);
  });
}

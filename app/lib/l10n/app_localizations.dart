import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('tr')];

  /// No description provided for @appTitle.
  ///
  /// In tr, this message translates to:
  /// **'Takvim'**
  String get appTitle;

  /// No description provided for @tabCalendar.
  ///
  /// In tr, this message translates to:
  /// **'Takvim'**
  String get tabCalendar;

  /// No description provided for @tabNotes.
  ///
  /// In tr, this message translates to:
  /// **'Notlar'**
  String get tabNotes;

  /// No description provided for @login.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yap'**
  String get login;

  /// No description provided for @register.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt ol'**
  String get register;

  /// No description provided for @logout.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yap'**
  String get logout;

  /// No description provided for @email.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get email;

  /// No description provided for @password.
  ///
  /// In tr, this message translates to:
  /// **'Parola'**
  String get password;

  /// No description provided for @serverUrl.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu adresi'**
  String get serverUrl;

  /// No description provided for @serverUrlHint.
  ///
  /// In tr, this message translates to:
  /// **'https://takvim.example.com'**
  String get serverUrlHint;

  /// No description provided for @noAccountRegister.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın yok mu? Kayıt ol'**
  String get noAccountRegister;

  /// No description provided for @haveAccountLogin.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın var mı? Giriş yap'**
  String get haveAccountLogin;

  /// No description provided for @invalidEmail.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir e-posta gir'**
  String get invalidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In tr, this message translates to:
  /// **'Parola en az 8 karakter olmalı'**
  String get passwordTooShort;

  /// No description provided for @authFailed.
  ///
  /// In tr, this message translates to:
  /// **'Giriş başarısız: {reason}'**
  String authFailed(String reason);

  /// No description provided for @networkError.
  ///
  /// In tr, this message translates to:
  /// **'Sunucuya ulaşılamadı'**
  String get networkError;

  /// No description provided for @syncStatusSynced.
  ///
  /// In tr, this message translates to:
  /// **'Senkronlandı'**
  String get syncStatusSynced;

  /// No description provided for @syncStatusPending.
  ///
  /// In tr, this message translates to:
  /// **'{count} bekleyen değişiklik'**
  String syncStatusPending(int count);

  /// No description provided for @syncStatusSyncing.
  ///
  /// In tr, this message translates to:
  /// **'Senkronlanıyor…'**
  String get syncStatusSyncing;

  /// No description provided for @syncStatusOffline.
  ///
  /// In tr, this message translates to:
  /// **'Çevrimdışı'**
  String get syncStatusOffline;

  /// No description provided for @syncStatusError.
  ///
  /// In tr, this message translates to:
  /// **'Senkron hatası'**
  String get syncStatusError;

  /// No description provided for @syncNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi senkronla'**
  String get syncNow;

  /// No description provided for @today.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get today;

  /// No description provided for @agenda.
  ///
  /// In tr, this message translates to:
  /// **'Ajanda'**
  String get agenda;

  /// No description provided for @month.
  ///
  /// In tr, this message translates to:
  /// **'Ay'**
  String get month;

  /// No description provided for @noEvents.
  ///
  /// In tr, this message translates to:
  /// **'Etkinlik yok'**
  String get noEvents;

  /// No description provided for @newEvent.
  ///
  /// In tr, this message translates to:
  /// **'Yeni etkinlik'**
  String get newEvent;

  /// No description provided for @newNote.
  ///
  /// In tr, this message translates to:
  /// **'Yeni not'**
  String get newNote;

  /// No description provided for @title.
  ///
  /// In tr, this message translates to:
  /// **'Başlık'**
  String get title;

  /// No description provided for @description.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama'**
  String get description;

  /// No description provided for @location.
  ///
  /// In tr, this message translates to:
  /// **'Konum'**
  String get location;

  /// No description provided for @start.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get start;

  /// No description provided for @end.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş'**
  String get end;

  /// No description provided for @allDay.
  ///
  /// In tr, this message translates to:
  /// **'Tüm gün'**
  String get allDay;

  /// No description provided for @calendar.
  ///
  /// In tr, this message translates to:
  /// **'Takvim'**
  String get calendar;

  /// No description provided for @save.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get delete;

  /// No description provided for @deleteConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Silinsin mi?'**
  String get deleteConfirm;

  /// No description provided for @titleRequired.
  ///
  /// In tr, this message translates to:
  /// **'Başlık gerekli'**
  String get titleRequired;

  /// No description provided for @endBeforeStart.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş, başlangıçtan önce olamaz'**
  String get endBeforeStart;

  /// No description provided for @searchNotes.
  ///
  /// In tr, this message translates to:
  /// **'Notlarda ara'**
  String get searchNotes;

  /// No description provided for @noNotes.
  ///
  /// In tr, this message translates to:
  /// **'Henüz not yok'**
  String get noNotes;

  /// No description provided for @noteBodyHint.
  ///
  /// In tr, this message translates to:
  /// **'Markdown ile yaz…'**
  String get noteBodyHint;

  /// No description provided for @tags.
  ///
  /// In tr, this message translates to:
  /// **'Etiketler (virgülle ayır)'**
  String get tags;

  /// No description provided for @pin.
  ///
  /// In tr, this message translates to:
  /// **'Sabitle'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In tr, this message translates to:
  /// **'Sabitlemeyi kaldır'**
  String get unpin;

  /// No description provided for @preview.
  ///
  /// In tr, this message translates to:
  /// **'Önizleme'**
  String get preview;

  /// No description provided for @edit.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle'**
  String get edit;

  /// No description provided for @noteEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Not boş olamaz'**
  String get noteEmpty;

  /// No description provided for @untitled.
  ///
  /// In tr, this message translates to:
  /// **'Başlıksız'**
  String get untitled;

  /// No description provided for @conflictCopy.
  ///
  /// In tr, this message translates to:
  /// **'(çakışan kopya)'**
  String get conflictCopy;

  /// No description provided for @retry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar dene'**
  String get retry;

  /// No description provided for @loading.
  ///
  /// In tr, this message translates to:
  /// **'Yükleniyor…'**
  String get loading;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'tr':
      return L10nTr();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

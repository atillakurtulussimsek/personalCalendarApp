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

  /// No description provided for @week.
  ///
  /// In tr, this message translates to:
  /// **'Hafta'**
  String get week;

  /// No description provided for @day.
  ///
  /// In tr, this message translates to:
  /// **'Gün'**
  String get day;

  /// No description provided for @repeat.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar'**
  String get repeat;

  /// No description provided for @noRepeat.
  ///
  /// In tr, this message translates to:
  /// **'Tekrarlama'**
  String get noRepeat;

  /// No description provided for @daily.
  ///
  /// In tr, this message translates to:
  /// **'Her gün'**
  String get daily;

  /// No description provided for @weekly.
  ///
  /// In tr, this message translates to:
  /// **'Her hafta'**
  String get weekly;

  /// No description provided for @monthly.
  ///
  /// In tr, this message translates to:
  /// **'Her ay'**
  String get monthly;

  /// No description provided for @yearly.
  ///
  /// In tr, this message translates to:
  /// **'Her yıl'**
  String get yearly;

  /// No description provided for @custom.
  ///
  /// In tr, this message translates to:
  /// **'Özel'**
  String get custom;

  /// No description provided for @every.
  ///
  /// In tr, this message translates to:
  /// **'Her'**
  String get every;

  /// No description provided for @interval.
  ///
  /// In tr, this message translates to:
  /// **'Aralık'**
  String get interval;

  /// No description provided for @unitDays.
  ///
  /// In tr, this message translates to:
  /// **'gün'**
  String get unitDays;

  /// No description provided for @unitWeeks.
  ///
  /// In tr, this message translates to:
  /// **'hafta'**
  String get unitWeeks;

  /// No description provided for @unitMonths.
  ///
  /// In tr, this message translates to:
  /// **'ay'**
  String get unitMonths;

  /// No description provided for @unitYears.
  ///
  /// In tr, this message translates to:
  /// **'yıl'**
  String get unitYears;

  /// No description provided for @ends.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş'**
  String get ends;

  /// No description provided for @never.
  ///
  /// In tr, this message translates to:
  /// **'Asla'**
  String get never;

  /// No description provided for @afterCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} tekrar sonra'**
  String afterCount(int count);

  /// No description provided for @onDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarihte'**
  String get onDate;

  /// No description provided for @done.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get done;

  /// No description provided for @reminders.
  ///
  /// In tr, this message translates to:
  /// **'Hatırlatıcılar'**
  String get reminders;

  /// No description provided for @addReminder.
  ///
  /// In tr, this message translates to:
  /// **'Hatırlatıcı ekle'**
  String get addReminder;

  /// No description provided for @minutesBefore.
  ///
  /// In tr, this message translates to:
  /// **'{minutes} dk önce'**
  String minutesBefore(int minutes);

  /// No description provided for @hoursBefore.
  ///
  /// In tr, this message translates to:
  /// **'{hours} saat önce'**
  String hoursBefore(int hours);

  /// No description provided for @daysBefore.
  ///
  /// In tr, this message translates to:
  /// **'{days} gün önce'**
  String daysBefore(int days);

  /// No description provided for @atStart.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıçta'**
  String get atStart;

  /// No description provided for @timezone.
  ///
  /// In tr, this message translates to:
  /// **'Saat dilimi'**
  String get timezone;

  /// No description provided for @notes.
  ///
  /// In tr, this message translates to:
  /// **'Notlar'**
  String get notes;

  /// No description provided for @addNote.
  ///
  /// In tr, this message translates to:
  /// **'Not ekle'**
  String get addNote;

  /// No description provided for @editScopeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Tekrarlayan etkinlik'**
  String get editScopeTitle;

  /// No description provided for @editScopeOnlyThis.
  ///
  /// In tr, this message translates to:
  /// **'Yalnızca bu'**
  String get editScopeOnlyThis;

  /// No description provided for @editScopeFollowing.
  ///
  /// In tr, this message translates to:
  /// **'Bu ve sonrakiler'**
  String get editScopeFollowing;

  /// No description provided for @editScopeAll.
  ///
  /// In tr, this message translates to:
  /// **'Tüm seri'**
  String get editScopeAll;

  /// No description provided for @calendars.
  ///
  /// In tr, this message translates to:
  /// **'Takvimler'**
  String get calendars;

  /// No description provided for @newCalendar.
  ///
  /// In tr, this message translates to:
  /// **'Yeni takvim'**
  String get newCalendar;

  /// No description provided for @editCalendar.
  ///
  /// In tr, this message translates to:
  /// **'Takvimi düzenle'**
  String get editCalendar;

  /// No description provided for @name.
  ///
  /// In tr, this message translates to:
  /// **'Ad'**
  String get name;

  /// No description provided for @color.
  ///
  /// In tr, this message translates to:
  /// **'Renk'**
  String get color;

  /// No description provided for @makeDefault.
  ///
  /// In tr, this message translates to:
  /// **'Varsayılan yap'**
  String get makeDefault;

  /// No description provided for @defaultCalendar.
  ///
  /// In tr, this message translates to:
  /// **'Varsayılan'**
  String get defaultCalendar;

  /// No description provided for @subscribeIcs.
  ///
  /// In tr, this message translates to:
  /// **'ICS takvimine abone ol'**
  String get subscribeIcs;

  /// No description provided for @icsUrl.
  ///
  /// In tr, this message translates to:
  /// **'ICS adresi'**
  String get icsUrl;

  /// No description provided for @icsHintHolidays.
  ///
  /// In tr, this message translates to:
  /// **'Örn. Türkiye resmî tatilleri'**
  String get icsHintHolidays;

  /// No description provided for @subscription.
  ///
  /// In tr, this message translates to:
  /// **'Abonelik (salt okunur)'**
  String get subscription;

  /// No description provided for @refresh.
  ///
  /// In tr, this message translates to:
  /// **'Yenile'**
  String get refresh;

  /// No description provided for @icsFetched.
  ///
  /// In tr, this message translates to:
  /// **'{count} etkinlik alındı'**
  String icsFetched(int count);

  /// No description provided for @icsFetchFailed.
  ///
  /// In tr, this message translates to:
  /// **'Takvim alınamadı: {reason}'**
  String icsFetchFailed(String reason);

  /// No description provided for @deleteCalendarConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Takvim ve içindeki tüm etkinlikler silinsin mi?'**
  String get deleteCalendarConfirm;

  /// No description provided for @cannotDeleteLast.
  ///
  /// In tr, this message translates to:
  /// **'Son takvim silinemez'**
  String get cannotDeleteLast;

  /// No description provided for @nameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Ad gerekli'**
  String get nameRequired;

  /// No description provided for @allDayEvents.
  ///
  /// In tr, this message translates to:
  /// **'Tüm gün'**
  String get allDayEvents;

  /// No description provided for @weekNumber.
  ///
  /// In tr, this message translates to:
  /// **'{n}. hafta'**
  String weekNumber(int n);

  /// No description provided for @nowLine.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi'**
  String get nowLine;

  /// No description provided for @quickCapture.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı ekle'**
  String get quickCapture;

  /// No description provided for @captureHint.
  ///
  /// In tr, this message translates to:
  /// **'yarın 15:00 veli toplantısı @okul'**
  String get captureHint;

  /// No description provided for @captureSaveEvent.
  ///
  /// In tr, this message translates to:
  /// **'Etkinlik olarak kaydet'**
  String get captureSaveEvent;

  /// No description provided for @captureSaveNote.
  ///
  /// In tr, this message translates to:
  /// **'Not olarak kaydet'**
  String get captureSaveNote;

  /// No description provided for @captureEvent.
  ///
  /// In tr, this message translates to:
  /// **'Etkinlik'**
  String get captureEvent;

  /// No description provided for @captureNote.
  ///
  /// In tr, this message translates to:
  /// **'Not'**
  String get captureNote;

  /// No description provided for @captureEdit.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle'**
  String get captureEdit;

  /// No description provided for @captureSaved.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedildi'**
  String get captureSaved;

  /// No description provided for @captureExamples.
  ///
  /// In tr, this message translates to:
  /// **'Örnekler: “cuma 10-12 seminer @salon”, “her pazartesi 9:00 toplantı”, “3 kasım 14.30 dişçi 30 dk önce hatırlat”'**
  String get captureExamples;

  /// No description provided for @settings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settings;

  /// No description provided for @settingsCaptureNotification.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim çubuğunda “Hızlı not” eylemi'**
  String get settingsCaptureNotification;

  /// No description provided for @settingsCaptureNotificationHint.
  ///
  /// In tr, this message translates to:
  /// **'Kalıcı bildirim; dokununca hızlı ekleme açılır'**
  String get settingsCaptureNotificationHint;

  /// No description provided for @settingsHotkey.
  ///
  /// In tr, this message translates to:
  /// **'Global kısayol'**
  String get settingsHotkey;

  /// No description provided for @settingsHotkeyHint.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı ekleme penceresini her yerden açar'**
  String get settingsHotkeyHint;

  /// No description provided for @settingsHideDock.
  ///
  /// In tr, this message translates to:
  /// **'Dock\'ta gizle (yalnızca menü çubuğu)'**
  String get settingsHideDock;

  /// No description provided for @settingsLaunchAtLogin.
  ///
  /// In tr, this message translates to:
  /// **'Girişte otomatik başlat'**
  String get settingsLaunchAtLogin;

  /// No description provided for @settingsAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap'**
  String get settingsAccount;

  /// No description provided for @settingsServer.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu'**
  String get settingsServer;

  /// No description provided for @trayShow.
  ///
  /// In tr, this message translates to:
  /// **'Pencereyi göster'**
  String get trayShow;

  /// No description provided for @trayQuit.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış'**
  String get trayQuit;

  /// No description provided for @trayNoEvents.
  ///
  /// In tr, this message translates to:
  /// **'Yaklaşan etkinlik yok'**
  String get trayNoEvents;

  /// No description provided for @trayUpcoming.
  ///
  /// In tr, this message translates to:
  /// **'Yaklaşan'**
  String get trayUpcoming;

  /// No description provided for @widgetToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get widgetToday;

  /// No description provided for @shortcutNewNote.
  ///
  /// In tr, this message translates to:
  /// **'Yeni not'**
  String get shortcutNewNote;

  /// No description provided for @shortcutNewEvent.
  ///
  /// In tr, this message translates to:
  /// **'Yeni etkinlik'**
  String get shortcutNewEvent;

  /// No description provided for @shortcutCapture.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı ekle'**
  String get shortcutCapture;

  /// No description provided for @shortcutToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get shortcutToday;

  /// No description provided for @hotkeyPressKeys.
  ///
  /// In tr, this message translates to:
  /// **'Tuş kombinasyonuna bas…'**
  String get hotkeyPressKeys;

  /// No description provided for @hotkeyClear.
  ///
  /// In tr, this message translates to:
  /// **'Kaldır'**
  String get hotkeyClear;

  /// No description provided for @reminderTitle.
  ///
  /// In tr, this message translates to:
  /// **'{title}'**
  String reminderTitle(String title);

  /// No description provided for @reminderBodyAt.
  ///
  /// In tr, this message translates to:
  /// **'{time} · {relative}'**
  String reminderBodyAt(String time, String relative);

  /// No description provided for @reminderNow.
  ///
  /// In tr, this message translates to:
  /// **'şimdi başlıyor'**
  String get reminderNow;

  /// No description provided for @reminderInMinutes.
  ///
  /// In tr, this message translates to:
  /// **'{minutes} dk sonra'**
  String reminderInMinutes(int minutes);

  /// No description provided for @settingsNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get settingsNotifications;

  /// No description provided for @settingsExactAlarm.
  ///
  /// In tr, this message translates to:
  /// **'Tam zamanlı hatırlatıcılar'**
  String get settingsExactAlarm;

  /// No description provided for @settingsExactAlarmHintOn.
  ///
  /// In tr, this message translates to:
  /// **'Açık: hatırlatıcılar tam dakikasında gelir'**
  String get settingsExactAlarmHintOn;

  /// No description provided for @settingsExactAlarmHintOff.
  ///
  /// In tr, this message translates to:
  /// **'Kapalı: Android pil tasarrufu nedeniyle bildirim birkaç dakika gecikebilir. Dokunup “Alarmlar ve hatırlatıcılar” iznini ver.'**
  String get settingsExactAlarmHintOff;

  /// No description provided for @settingsNotificationPermission.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim izni'**
  String get settingsNotificationPermission;

  /// No description provided for @settingsNotificationPermissionHint.
  ///
  /// In tr, this message translates to:
  /// **'Hatırlatıcıların görünmesi için gerekli'**
  String get settingsNotificationPermissionHint;

  /// No description provided for @settingsBatteryHint.
  ///
  /// In tr, this message translates to:
  /// **'Xiaomi/Huawei gibi cihazlarda uygulamanın pil kısıtlamasını kaldırmanız gerekebilir.'**
  String get settingsBatteryHint;

  /// No description provided for @settingsLiveSync.
  ///
  /// In tr, this message translates to:
  /// **'Canlı senkron'**
  String get settingsLiveSync;

  /// No description provided for @settingsLiveSyncHint.
  ///
  /// In tr, this message translates to:
  /// **'Diğer cihazlardaki değişiklikler anında gelir (WebSocket / FCM)'**
  String get settingsLiveSyncHint;

  /// No description provided for @permissionDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hatırlatıcı izinleri'**
  String get permissionDialogTitle;

  /// No description provided for @permissionDialogBody.
  ///
  /// In tr, this message translates to:
  /// **'Hatırlatıcıların zamanında görünmesi için bildirim izni ve Android 12+ üzerinde “Alarmlar ve hatırlatıcılar” izni gerekir. Pil tasarrufu (Doze) modunda tam zamanlı alarm izni olmadan bildirimler gecikebilir.'**
  String get permissionDialogBody;

  /// No description provided for @permissionDialogAllow.
  ///
  /// In tr, this message translates to:
  /// **'İzin ver'**
  String get permissionDialogAllow;

  /// No description provided for @permissionDialogLater.
  ///
  /// In tr, this message translates to:
  /// **'Sonra'**
  String get permissionDialogLater;

  /// No description provided for @liveStatusConnected.
  ///
  /// In tr, this message translates to:
  /// **'Canlı'**
  String get liveStatusConnected;

  /// No description provided for @liveStatusDisconnected.
  ///
  /// In tr, this message translates to:
  /// **'Canlı bağlantı yok'**
  String get liveStatusDisconnected;
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

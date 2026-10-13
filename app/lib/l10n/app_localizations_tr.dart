// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class L10nTr extends L10n {
  L10nTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'Takvim';

  @override
  String get tabCalendar => 'Takvim';

  @override
  String get tabNotes => 'Notlar';

  @override
  String get login => 'Giriş yap';

  @override
  String get register => 'Kayıt ol';

  @override
  String get logout => 'Çıkış yap';

  @override
  String get email => 'E-posta';

  @override
  String get password => 'Parola';

  @override
  String get serverUrl => 'Sunucu adresi';

  @override
  String get serverUrlHint => 'https://takvim.example.com';

  @override
  String get noAccountRegister => 'Hesabın yok mu? Kayıt ol';

  @override
  String get haveAccountLogin => 'Hesabın var mı? Giriş yap';

  @override
  String get invalidEmail => 'Geçerli bir e-posta gir';

  @override
  String get passwordTooShort => 'Parola en az 8 karakter olmalı';

  @override
  String authFailed(String reason) {
    return 'Giriş başarısız: $reason';
  }

  @override
  String get networkError => 'Sunucuya ulaşılamadı';

  @override
  String get syncStatusSynced => 'Senkronlandı';

  @override
  String syncStatusPending(int count) {
    return '$count bekleyen değişiklik';
  }

  @override
  String get syncStatusSyncing => 'Senkronlanıyor…';

  @override
  String get syncStatusOffline => 'Çevrimdışı';

  @override
  String get syncStatusError => 'Senkron hatası';

  @override
  String get syncNow => 'Şimdi senkronla';

  @override
  String get today => 'Bugün';

  @override
  String get agenda => 'Ajanda';

  @override
  String get month => 'Ay';

  @override
  String get noEvents => 'Etkinlik yok';

  @override
  String get newEvent => 'Yeni etkinlik';

  @override
  String get newNote => 'Yeni not';

  @override
  String get title => 'Başlık';

  @override
  String get description => 'Açıklama';

  @override
  String get location => 'Konum';

  @override
  String get start => 'Başlangıç';

  @override
  String get end => 'Bitiş';

  @override
  String get allDay => 'Tüm gün';

  @override
  String get calendar => 'Takvim';

  @override
  String get save => 'Kaydet';

  @override
  String get cancel => 'İptal';

  @override
  String get delete => 'Sil';

  @override
  String get deleteConfirm => 'Silinsin mi?';

  @override
  String get titleRequired => 'Başlık gerekli';

  @override
  String get endBeforeStart => 'Bitiş, başlangıçtan önce olamaz';

  @override
  String get searchNotes => 'Notlarda ara';

  @override
  String get noNotes => 'Henüz not yok';

  @override
  String get noteBodyHint => 'Markdown ile yaz…';

  @override
  String get tags => 'Etiketler (virgülle ayır)';

  @override
  String get pin => 'Sabitle';

  @override
  String get unpin => 'Sabitlemeyi kaldır';

  @override
  String get preview => 'Önizleme';

  @override
  String get edit => 'Düzenle';

  @override
  String get noteEmpty => 'Not boş olamaz';

  @override
  String get untitled => 'Başlıksız';

  @override
  String get conflictCopy => '(çakışan kopya)';

  @override
  String get retry => 'Tekrar dene';

  @override
  String get loading => 'Yükleniyor…';

  @override
  String get week => 'Hafta';

  @override
  String get day => 'Gün';

  @override
  String get repeat => 'Tekrar';

  @override
  String get noRepeat => 'Tekrarlama';

  @override
  String get daily => 'Her gün';

  @override
  String get weekly => 'Her hafta';

  @override
  String get monthly => 'Her ay';

  @override
  String get yearly => 'Her yıl';

  @override
  String get custom => 'Özel';

  @override
  String get every => 'Her';

  @override
  String get interval => 'Aralık';

  @override
  String get unitDays => 'gün';

  @override
  String get unitWeeks => 'hafta';

  @override
  String get unitMonths => 'ay';

  @override
  String get unitYears => 'yıl';

  @override
  String get ends => 'Bitiş';

  @override
  String get never => 'Asla';

  @override
  String afterCount(int count) {
    return '$count tekrar sonra';
  }

  @override
  String get onDate => 'Tarihte';

  @override
  String get done => 'Tamam';

  @override
  String get reminders => 'Hatırlatıcılar';

  @override
  String get addReminder => 'Hatırlatıcı ekle';

  @override
  String minutesBefore(int minutes) {
    return '$minutes dk önce';
  }

  @override
  String hoursBefore(int hours) {
    return '$hours saat önce';
  }

  @override
  String daysBefore(int days) {
    return '$days gün önce';
  }

  @override
  String get atStart => 'Başlangıçta';

  @override
  String get timezone => 'Saat dilimi';

  @override
  String get notes => 'Notlar';

  @override
  String get addNote => 'Not ekle';

  @override
  String get editScopeTitle => 'Tekrarlayan etkinlik';

  @override
  String get editScopeOnlyThis => 'Yalnızca bu';

  @override
  String get editScopeFollowing => 'Bu ve sonrakiler';

  @override
  String get editScopeAll => 'Tüm seri';

  @override
  String get calendars => 'Takvimler';

  @override
  String get newCalendar => 'Yeni takvim';

  @override
  String get editCalendar => 'Takvimi düzenle';

  @override
  String get name => 'Ad';

  @override
  String get color => 'Renk';

  @override
  String get makeDefault => 'Varsayılan yap';

  @override
  String get defaultCalendar => 'Varsayılan';

  @override
  String get subscribeIcs => 'ICS takvimine abone ol';

  @override
  String get icsUrl => 'ICS adresi';

  @override
  String get icsHintHolidays => 'Örn. Türkiye resmî tatilleri';

  @override
  String get subscription => 'Abonelik (salt okunur)';

  @override
  String get refresh => 'Yenile';

  @override
  String icsFetched(int count) {
    return '$count etkinlik alındı';
  }

  @override
  String icsFetchFailed(String reason) {
    return 'Takvim alınamadı: $reason';
  }

  @override
  String get deleteCalendarConfirm =>
      'Takvim ve içindeki tüm etkinlikler silinsin mi?';

  @override
  String get cannotDeleteLast => 'Son takvim silinemez';

  @override
  String get nameRequired => 'Ad gerekli';

  @override
  String get allDayEvents => 'Tüm gün';

  @override
  String weekNumber(int n) {
    return '$n. hafta';
  }

  @override
  String get nowLine => 'Şimdi';

  @override
  String get quickCapture => 'Hızlı ekle';

  @override
  String get captureHint => 'yarın 15:00 veli toplantısı @okul';

  @override
  String get captureSaveEvent => 'Etkinlik olarak kaydet';

  @override
  String get captureSaveNote => 'Not olarak kaydet';

  @override
  String get captureEvent => 'Etkinlik';

  @override
  String get captureNote => 'Not';

  @override
  String get captureEdit => 'Düzenle';

  @override
  String get captureSaved => 'Kaydedildi';

  @override
  String get captureExamples =>
      'Örnekler: “cuma 10-12 seminer @salon”, “her pazartesi 9:00 toplantı”, “3 kasım 14.30 dişçi 30 dk önce hatırlat”';

  @override
  String get settings => 'Ayarlar';

  @override
  String get settingsCaptureNotification =>
      'Bildirim çubuğunda “Hızlı not” eylemi';

  @override
  String get settingsCaptureNotificationHint =>
      'Kalıcı bildirim; dokununca hızlı ekleme açılır';

  @override
  String get settingsHotkey => 'Global kısayol';

  @override
  String get settingsHotkeyHint => 'Hızlı ekleme penceresini her yerden açar';

  @override
  String get settingsHideDock => 'Dock\'ta gizle (yalnızca menü çubuğu)';

  @override
  String get settingsLaunchAtLogin => 'Girişte otomatik başlat';

  @override
  String get settingsAccount => 'Hesap';

  @override
  String get settingsServer => 'Sunucu';

  @override
  String get trayShow => 'Pencereyi göster';

  @override
  String get trayQuit => 'Çıkış';

  @override
  String get trayNoEvents => 'Yaklaşan etkinlik yok';

  @override
  String get trayUpcoming => 'Yaklaşan';

  @override
  String get widgetToday => 'Bugün';

  @override
  String get shortcutNewNote => 'Yeni not';

  @override
  String get shortcutNewEvent => 'Yeni etkinlik';

  @override
  String get shortcutCapture => 'Hızlı ekle';

  @override
  String get shortcutToday => 'Bugün';

  @override
  String get hotkeyPressKeys => 'Tuş kombinasyonuna bas…';

  @override
  String get hotkeyClear => 'Kaldır';
}

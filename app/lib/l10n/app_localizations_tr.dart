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

  @override
  String reminderTitle(String title) {
    return '$title';
  }

  @override
  String reminderBodyAt(String time, String relative) {
    return '$time · $relative';
  }

  @override
  String get reminderNow => 'şimdi başlıyor';

  @override
  String reminderInMinutes(int minutes) {
    return '$minutes dk sonra';
  }

  @override
  String get settingsNotifications => 'Bildirimler';

  @override
  String get settingsExactAlarm => 'Tam zamanlı hatırlatıcılar';

  @override
  String get settingsExactAlarmHintOn =>
      'Açık: hatırlatıcılar tam dakikasında gelir';

  @override
  String get settingsExactAlarmHintOff =>
      'Kapalı: Android pil tasarrufu nedeniyle bildirim birkaç dakika gecikebilir. Dokunup “Alarmlar ve hatırlatıcılar” iznini ver.';

  @override
  String get settingsNotificationPermission => 'Bildirim izni';

  @override
  String get settingsNotificationPermissionHint =>
      'Hatırlatıcıların görünmesi için gerekli';

  @override
  String get settingsBatteryHint =>
      'Xiaomi/Huawei gibi cihazlarda uygulamanın pil kısıtlamasını kaldırmanız gerekebilir.';

  @override
  String get settingsLiveSync => 'Canlı senkron';

  @override
  String get settingsLiveSyncHint =>
      'Diğer cihazlardaki değişiklikler anında gelir (WebSocket / FCM)';

  @override
  String get permissionDialogTitle => 'Hatırlatıcı izinleri';

  @override
  String get permissionDialogBody =>
      'Hatırlatıcıların zamanında görünmesi için bildirim izni ve Android 12+ üzerinde “Alarmlar ve hatırlatıcılar” izni gerekir. Pil tasarrufu (Doze) modunda tam zamanlı alarm izni olmadan bildirimler gecikebilir.';

  @override
  String get permissionDialogAllow => 'İzin ver';

  @override
  String get permissionDialogLater => 'Sonra';

  @override
  String get liveStatusConnected => 'Canlı';

  @override
  String get liveStatusDisconnected => 'Canlı bağlantı yok';

  @override
  String get tabTasks => 'Görevler';

  @override
  String get newTask => 'Yeni görev';

  @override
  String get taskTitleHint => 'Ne yapılacak?';

  @override
  String get dueDate => 'Son tarih';

  @override
  String get noDueDate => 'Tarih yok';

  @override
  String get taskDone => 'Tamamlandı';

  @override
  String get taskOpen => 'Açık';

  @override
  String get noTasks => 'Görev yok';

  @override
  String get showDone => 'Tamamlananları göster';

  @override
  String get hideDone => 'Tamamlananları gizle';

  @override
  String get overdue => 'Gecikmiş';

  @override
  String get captureSaveTask => 'Görev olarak kaydet';

  @override
  String get linkedNote => 'Bağlı not';

  @override
  String get taskDeleted => 'Görev silindi';

  @override
  String get settingsAppearance => 'Görünüm';

  @override
  String get themeSystem => 'Sistem';

  @override
  String get themeLight => 'Açık';

  @override
  String get themeDark => 'Koyu';

  @override
  String get settingsDefaultReminder => 'Varsayılan hatırlatıcı';

  @override
  String get settingsData => 'Veri';

  @override
  String get importIcs => 'ICS dosyası içe aktar';

  @override
  String get importIcsHint =>
      'Seçilen takvime etkinlik olarak eklenir (senkronlanır)';

  @override
  String get exportIcs => 'ICS olarak dışa aktar';

  @override
  String importDone(int count) {
    return '$count etkinlik içe aktarıldı';
  }

  @override
  String exportDone(String path) {
    return 'Dışa aktarıldı: $path';
  }

  @override
  String importFailed(String reason) {
    return 'İçe aktarma başarısız: $reason';
  }

  @override
  String get chooseCalendar => 'Takvim seç';

  @override
  String get none => 'Yok';

  @override
  String get tabToday => 'Bugün';

  @override
  String get greetingMorning => 'Günaydın';

  @override
  String get greetingDay => 'İyi günler';

  @override
  String get greetingEvening => 'İyi akşamlar';

  @override
  String get greetingNight => 'İyi geceler';

  @override
  String greetingWithName(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get nextUp => 'Sıradaki';

  @override
  String get happeningNow => 'Şu an';

  @override
  String inMinutes(int minutes) {
    return '$minutes dk sonra';
  }

  @override
  String inHoursMinutes(int hours, int minutes) {
    return '$hours sa $minutes dk sonra';
  }

  @override
  String inHours(int hours) {
    return '$hours sa sonra';
  }

  @override
  String endsInMinutes(int minutes) {
    return '$minutes dk kaldı';
  }

  @override
  String get tomorrowFirst => 'Yarın ilk etkinlik';

  @override
  String get tomorrow => 'Yarın';

  @override
  String eventsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etkinlik',
      zero: 'Etkinlik yok',
    );
    return '$_temp0';
  }

  @override
  String daySummary(int events, int done, int total) {
    return 'Bugün $events etkinlik, $done/$total görev tamam. Güzel bir gündü.';
  }

  @override
  String get freeDayTitle => 'Takvimin boş';

  @override
  String get freeDayBody =>
      'Bugün etkinlik yok. Bir şey planlamak istersen aşağıya yazman yeter.';

  @override
  String get captureHintToday => 'Ne var aklında?';

  @override
  String get captureHintCalendar => 'Bu güne ekle…';

  @override
  String get captureHintNotes => 'Yeni not…';

  @override
  String get captureHintTasks => 'Yeni görev…';

  @override
  String get tasksAllDone => 'Hepsi tamam, harikasın';

  @override
  String get tasksGoingWell => 'Bugün iyi gidiyorsun';

  @override
  String get tasksStart => 'Hadi başlayalım';

  @override
  String get tasksNoneToday => 'Bugün için görev yok';

  @override
  String tasksRemaining(int count) {
    return '$count görev kaldı';
  }

  @override
  String overdueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tanesi gecikmiş',
      one: 'biri gecikmiş',
    );
    return '$_temp0';
  }

  @override
  String get later => 'Daha sonra';

  @override
  String get doneSection => 'Tamamlananlar';

  @override
  String get emptyTasksTitle => 'Her şey yolunda';

  @override
  String get emptyTasksBody =>
      'Bekleyen görev yok. Aklına bir şey gelirse aşağıya yaz, tarihini ben anlarım.';

  @override
  String get emptyNotesTitle => 'İlk notunu yaz';

  @override
  String get emptyNotesBody =>
      'Fikirler, listeler, toplantı notları. Markdown ve #etiket desteklenir.';

  @override
  String get exampleTask1 => 'yarın faturayı öde';

  @override
  String get exampleTask2 => 'cuma rapor gönder';

  @override
  String get exampleNote1 => 'Kitap önerileri';

  @override
  String get exampleEvent1 => 'yarın 15:00 toplantı';

  @override
  String get pinnedSection => 'Sabitlenmiş';

  @override
  String get recentNotes => 'Son düzenlenenler';

  @override
  String get recentSearches => 'Son aramalar';

  @override
  String get tagsSection => 'Etiketler';

  @override
  String get linkedThisWeek => 'Bu haftanın etkinliklerine bağlı notlar';

  @override
  String get noResults => 'Sonuç yok';

  @override
  String get captureUnderstood => 'Şöyle anladım — düzeltmek için dokun';

  @override
  String get captureKeysHint => '↵ kaydet · ⇧↵ not';

  @override
  String get savedEvent => 'Takvime eklendi';

  @override
  String get savedNote => 'Not kaydedildi';

  @override
  String get savedTask => 'Görev eklendi';

  @override
  String willRemindAt(String when) {
    return 'Hatırlatma: $when';
  }

  @override
  String get undo => 'Geri al';

  @override
  String get captureTask => 'Görev';

  @override
  String get captureNoteShort => 'Not';

  @override
  String get welcomeBack => 'Tekrar hoş geldin';

  @override
  String get createAccount => 'Hesap oluştur';

  @override
  String get haveAccount => 'Zaten hesabım var';

  @override
  String get loginSubtitle => 'Takvimin ve notların cihazlarınla senkron.';

  @override
  String get registerSubtitle =>
      'Birkaç saniyede başla; verilerin kendi sunucunda kalır.';

  @override
  String serverLine(String host) {
    return 'Sunucu: $host';
  }

  @override
  String get change => 'değiştir';

  @override
  String get eventTitle => 'Etkinlik';

  @override
  String durationLabel(String text) {
    return '$text';
  }

  @override
  String get addNoteToEvent => 'Bu etkinliğe not ekle';

  @override
  String get newBadge => 'Yeni';

  @override
  String get thisWeek => 'Bu hafta';

  @override
  String get syncOk => 'Senkron';

  @override
  String get titleHint => 'Başlık';
}

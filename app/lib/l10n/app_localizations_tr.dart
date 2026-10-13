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
}

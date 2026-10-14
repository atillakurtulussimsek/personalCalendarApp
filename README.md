# Personal Calendar

Kişisel takvim + anlık not uygulaması. Android ve macOS istemcileri (Flutter), kendi
sunucunuzda çalışan Go API (Dokploy ile dağıtım), çevrimdışı öncelikli senkronizasyon.

```
backend/   Go API           → backend/README.md (çalıştırma, test, Dokploy)
app/       Flutter uygulaması (Android, macOS, web)
docs/      mimari, API (OpenAPI), karar günlüğü
```

## Durum

| Faz | İçerik | Durum |
|-----|--------|-------|
| 1 | Backend temeli: auth, CRUD, `/sync`, RRULE genişletme, testler, Docker | ✅ |
| 2 | Flutter temeli: drift, auth, outbox + sync, notlar, ay/ajanda | ✅ |
| 3 | Takvim derinliği: hafta/gün, sürükle-bırak, tekrar kuralları, istisnalar, ICS abonelik | ✅ |
| 4 | Anlık yakalama: Türkçe ayrıştırıcı, Android widget/tile/paylaş/bildirim/kısayol, macOS menü çubuğu + global kısayol | ✅ |
| 5 | Bildirimler ve canlı senkron: yerel hatırlatıcılar, WebSocket, FCM, WorkManager | ✅ |
| 6 | Cilalama: görevler, ICS içe/dışa aktarma, yedekleme, tema ayarı | ✅ (CalDAV yapılmadı) |

## Build

Tek komut, API + web arayüzü tek binary'de:

```bash
make build            # → backend/bin/api  (http://sunucu:8080/ web arayüzü, aynı porttan API)
make run              # build + çalıştır (backend/.env okunur)
docker build -t personal-calendar .   # aynısı, container olarak
```

Yerel istemciler:

```bash
make apk              # Android
make macos            # macOS (Xcode + CocoaPods gerekir)
```

Dokploy'a dağıtım: [backend/README.md](backend/README.md#deploy-to-dokploy).

## Hızlı başlangıç (backend)

```bash
cd backend
cp .env.example .env     # DATABASE_URL ve JWT_SECRET doldur
make run
```

Ayrıntılar: [backend/README.md](backend/README.md) · API: [docs/api.yaml](docs/api.yaml) ·
Mimari ve sync protokolü: [docs/architecture.md](docs/architecture.md) ·
Kararlar: [docs/decisions.md](docs/decisions.md)

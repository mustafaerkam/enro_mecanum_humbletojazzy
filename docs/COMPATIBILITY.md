# Uyumluluk

| Alan | Hedef / durum |
|---|---|
| Docker host | Ubuntu 22.04; container Ubuntu 24.04 |
| Native PC | Ubuntu 24.04 amd64, ROS 2 Jazzy |
| Sim | Gazebo Harmonic, `ros_gz`, `gz_ros2_control` |
| Gerçek | Pi 5 arm64, Ubuntu 24.04, ROS 2 Jazzy |
| DDS | Fast DDS, domain 42 |

## Doğrulanmış ortam (10 Eylül 2026)

Aşağıdaki kombinasyon Ubuntu 22.04 host üzerinde Docker içinde **fiilen
çalıştırılarak** doğrulanmıştır.

| Alan | Değer |
|---|---|
| Kaynak durumu | Tek snapshot commit; SHA yayın sırasında atanır |
| Host | Ubuntu 22.04, Docker 29.1.3, Compose 2.40.3 |
| Container | Ubuntu 24.04 (noble), amd64 (x86_64) |
| Taban imaj | `ros:jazzy-ros-base-noble@sha256:386d06ec6d4188f731bae5678e07b4cb64a4e4d4152090c0bd1f881dcf7706f5` |
| ROS | Jazzy |
| Gazebo | Harmonic (gz sim 8.11.0) |
| ros2_control | 4.45.2-1noble.20260615.171757 |
| ros2_controllers | 4.40.1-1noble.20260616.074625 |
| gz_ros2_control | 1.2.19-1noble.20260615.171757 |
| ros_gz_sim | 1.0.22-1noble.20260615.173223 |
| nav2_bringup | 1.3.12-1noble.20260616.082701 |
| slam_toolbox | 2.8.5-1noble.20260615.161600 |
| rplidar_ros | 2.1.0-4noble.20260615.142100 |

### Doğrulanan akışlar

| Kontrol | Sonuç |
|---|---|
| `./scripts/build_jazzy.sh` (7 paket) | PASS |
| `./scripts/test_jazzy.sh` (16 test, 0 error, 0 failure, 2 skipped) | PASS |
| Statik contract audit (13 kontrol) | PASS |
| `check_urdf` | PASS |
| Gazebo Harmonic açılışı + robot spawn | PASS |
| controller_manager + 2 controller active | PASS |
| İleri hareket (izleme hatası 0.024 m, odom-GT %0.6) | PASS |
| Yanal hareket (izleme hatası 0.120 m, odom-GT %0.2) | PASS |
| Dönüş (izleme hatası 0.031 rad, odom-GT %0.0) | PASS |
| Nav2 lifecycle düğümleri active | PASS |
| SLAM (slam_toolbox active, /map, map->odom tek sahip) | PASS |
| Harita kaydetme (`map_saver_cli` -> .pgm + .yaml) | PASS |
| Nav2 8 lifecycle düğümü active | PASS |
| Nav2 hedef (NavigateToPose) kabulü + SUCCEEDED | PASS |
| Komut zinciri uçtan uca TwistStamped | PASS |
| `./scripts/smoke_jazzy.sh nav` | PASS |
| `./scripts/smoke_jazzy.sh mapping` | PASS |
| Altı yön hareket + `NavigateToPose` status 4 (`SUCCEEDED`) | PASS |
| `./scripts/smoke_real_mock.sh nav` | PASS (donanımsız arayüz/lifecycle) |
| `./scripts/smoke_real_mock.sh mapping` | PASS (donanımsız arayüz/lifecycle) |
| Sıfır build/install/log + önbelleksiz Docker image + yeniden build/test | PASS |
| Smoke testleri yazılım rasterizer ile (GPU'suz, CI) | PASS |
| Kendi SLAM haritasıyla Nav2 (`map:=`) hedefi | PASS |
| Ubuntu 24.04 amd64 native fresh-checkout | PASS (GitHub Actions, temiz runner) |
| Pi 5 / arm64 native build | BLOCKED (fiziksel donanım yok) |
| Gerçek araç hareket testi | BLOCKED (firmware + donanım yok) |

### Bilinen kısıtlamalar

- LiDAR modeli RPLIDAR A1M8 olarak netleşti. USB vendor/product/serial
  kimlikleri, gerçek motor/encoder yönleri ve gerçek araç hız/fren limitleri
  hâlâ `CALIBRATION_REQUIRED` olarak işaretlidir.
- arm64 doğrulaması yapılmadı; yalnızca amd64 test edildi.
- Yanal harekette ~%16 izleme eksikliği vardır (0.627 m / 0.747 m).
  Mecanum makara temas modelinin beklenen kaybıdır; ana akışı
  engellemez. TODO: sürtünme/tuning incelemesi.
- TODO (ana akışı engellemez) — araç profili
  (`config/vehicles/reference_mecanum.yaml`) şu anda **kayıt/referans**
  belgesidir; Xacro ve controller YAML değerlerini otomatik beslemez.
  Geometri değişikliği hâlâ birden fazla dosyada elle yapılır
  ([NEW_VEHICLE.md](NEW_VEHICLE.md)).
- TODO (ana akışı engellemez) — Nav2 hedef toleransı: NavigateToPose
  SUCCEEDED döndü, ancak duran robotta AMCL pozu hedeften 0.37 m,
  ground truth ise 0.28 m uzaktaydı; yapılandırılmış
  `xy_goal_tolerance` 0.25 m'dir. AMCL ile ground truth arasinda ayrica
  ~0.09 m fark olculdu. Hedefe ulasma akisi calisiyor; tolerans/
  lokalizasyon tuning'i incelenmelidir.

### Çalışma zamanı doğrulaması (CI)

Statik testler (`contract_audit`, `check_urdf`) port sırasında ortaya çıkan
**iki gerçek hatayı yakalayamadı**; ikisi de yalnızca çalışma zamanında
görünüyordu (fdir1 friction frame, slam_toolbox lifecycle). Bu yüzden CI'da
gerçek bir headless simülasyon açan smoke testleri çalışır:

```bash
./scripts/smoke_jazzy.sh nav        # controller, topic, TwistStamped zinciri, TF, Nav2 lifecycle
./scripts/smoke_jazzy.sh mapping    # + slam_toolbox lifecycle, /map, map->odom, harita kaydetme
./scripts/smoke_real_mock.sh nav    # gercek launch agaci, mock transport
./scripts/smoke_real_mock.sh mapping
```

CI'ın native işi container kullanmadan temiz Ubuntu 24.04 runner'a ROS 2 Jazzy
kurup fresh checkout üzerinde build/test ve URDF kontrolünü başarıyla tamamladı.
Docker işi sabit digest'li container içinde headless simülasyon ve mock gerçek
araç profillerini çalıştırır.

GitHub runner'inda GPU olmadigi icin CI yazilim rasterizer kullanir
(`LIBGL_ALWAYS_SOFTWARE=1`, `GALLIUM_DRIVER=llvmpipe`); bu konfigurasyon
yerelde de dogrulandi.

### Kritik port notu — fdir1 friction frame

Mecanum yanal hareketi için `fdir1` **gerçek bir SDF link'ine**
bağlanmalıdır. `urdf`→`sdf` dönüşümü sabit eklemli `base_link`'i
`base_footprint` içine lump eder ve `base_link` yalnızca bir SDF
`frame` elemanı olarak kalır. dartsim ise friction direction frame'i
için body node ister; çözülemeyen frame **sessizce** yok sayılır ve
sürtünme yönü tekerle birlikte döner.

Belirti: sabit teker hızında gövde yanal hızı işaret değiştirerek
salınır (salınım periyodu = teker dönüş periyodu) ve aynı komut ardışık
koşularda zıt sonuç verir. Bu bir teker sırası/çapraz hatası **değildir**.

Doğrusu: `gz:expressed_in="base_footprint"`. Çaprazlar Harmonic'in resmî
`mecanum_drive.sdf` dünyasıyla aynıdır (FL/RR = 1 -1 0, FR/RL = 1 1 0).

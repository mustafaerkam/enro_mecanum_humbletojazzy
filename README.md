# enro_mecanum_humbletojazzy

Dört tekerlekli mecanum robotun **ROS 2 Jazzy + Gazebo Harmonic** high-level
stack'i: `ros2_control`, SLAM Toolbox, Nav2 ve güvenlik zinciri.

- **Simülasyon**, ESP32 / seri port / micro-ROS agent olmadan **bağımsız** çalışır.
- **Gerçek araç** yolu Raspberry Pi 5 üzerinde **native** Jazzy kullanır.
- **Firmware bu repository'de değildir**; beklenen arayüz
  [docs/LOW_LEVEL_INTERFACE.md](docs/LOW_LEVEL_INTERFACE.md) içinde tanımlıdır.

Bu proje ROS 2 Humble + Gazebo Fortress tabanlı bir sistemden portlanmıştır.
Doğrulanmış sürüm kombinasyonu ve test sonuçları:
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

---

## Hangi yolu izlemeliyim?

Üç desteklenen kullanıcı yolu vardır. Bilgisayarınıza göre birini seçin:

| | Yol | Kimin için | Bölüm |
|---|---|---|---|
| **1** | Ubuntu 24.04 + native Jazzy | Doğru işletim sistemi zaten kurulu | [↓ Yol 1](#yol-1--ubuntu-2404--native-jazzy) |
| **2** | Ubuntu 22.04 + Jazzy Docker | Humble'da kalması gereken makine | [↓ Yol 2](#yol-2--ubuntu-2204--jazzy-docker) |
| **3** | Raspberry Pi 5 gerçek araç | Fiziksel robot (arm64) | [↓ Yol 3](#yol-3--raspberry-pi-5-gerçek-araç) |

Yol 1 ve Yol 2 **aynı** simülasyon akışını çalıştırır; tek fark stack'in host'ta
mı yoksa konteynerde mi olduğudur. Yol 3 simülasyon içermez.

> **Uyarı — aynı anda çalıştırmayın:** `sim_nav` ve `sim_mapping` profilleri
> birlikte başlatılamaz. İkisi de `map -> odom` TF'ini yayınlar (AMCL ve
> slam_toolbox); ikisi birden çalışırsa TF ağacı bozulur.

---

## Yol 1 — Ubuntu 24.04 + native Jazzy

**Önkoşul:** Ubuntu 24.04 amd64. Başka Ubuntu sürümünde bu yolu kullanmayın.

### 1.1 ROS 2 Jazzy kurulumu (Jazzy zaten kuruluysa atlayın)

ROS 2'nin resmî Ubuntu paket kaynağını ekleyip Desktop kurulumunu yapın:

```bash
sudo apt update
sudo apt install -y software-properties-common curl
sudo add-apt-repository universe

export ROS_APT_SOURCE_VERSION="$(curl -s \
  https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
  | grep -F 'tag_name' | awk -F'"' '{print $4}')"
curl -L -o /tmp/ros2-apt-source.deb \
  "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb

sudo apt update
sudo apt upgrade -y
sudo apt install -y ros-jazzy-desktop ros-dev-tools
source /opt/ros/jazzy/setup.bash
```

Kurulumun her terminalde otomatik kaynaklanmasını isterseniz:

```bash
echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc
```

Resmî kurulum kaynağı: [ROS 2 Jazzy Ubuntu deb kurulumu](https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html).

### 1.2 Repository ve derleme

```bash
git clone https://github.com/mustafaerkam/enro_mecanum_humbletojazzy.git
cd enro_mecanum_humbletojazzy

source /opt/ros/jazzy/setup.bash
./scripts/build_jazzy.sh          # rosdep install + colcon build
source install_jazzy/setup.bash
```

`build_jazzy.sh` çıktıları `build_jazzy/`, `install_jazzy/`, `log_jazzy/`
dizinlerine yazar — Humble çıktılarıyla **karışmaz**.

### 1.3 Simülasyon + Nav2 (kayıtlı harita)

```bash
ros2 launch mecanum_bringup sim_nav.launch.py
```

Gazebo Harmonic ve RViz açılır. AMCL başlangıç pozu **otomatik** verilir
(`auto_initial_pose:=true`), yani RViz'de elle poz vermeniz gerekmez.

RViz'de **"2D Goal Pose"** ile hedef verin; robot otonom gider.

Komut satırından hedef vermek isterseniz:

```bash
ros2 action send_goal /navigate_to_pose nav2_msgs/action/NavigateToPose \
  "{pose: {header: {frame_id: map}, pose: {position: {x: 0.5, y: 1.5}, orientation: {w: 1.0}}}}"
```

### 1.4 Teleop (ayrı terminal)

Teleop klavye girişi gerektirdiği için **ayrı bir terminalde** başlatılır:

```bash
cd enro_mecanum_humbletojazzy
source /opt/ros/jazzy/setup.bash
source install_jazzy/setup.bash
ros2 run mecanum_teleop teleop_node
```

Mecanum robot **holonomiktir**: ileri/geri, sağa/sola **yanal kayma (strafe)**
ve yerinde dönüş yapabilir.

### 1.5 SLAM ile kendi haritanızı çıkarma

Önce Nav2 oturumunu kapatın (Ctrl+C), sonra:

```bash
ros2 launch mecanum_bringup sim_mapping.launch.py
```

Ayrı terminalde teleop başlatıp robotu gezdirin; harita RViz'de büyür.

Harita yeterince tamamlanınca **üçüncü** bir terminalde kaydedin:

```bash
source /opt/ros/jazzy/setup.bash
source install_jazzy/setup.bash
ros2 run nav2_map_server map_saver_cli -f ~/mecanum_harita \
  --ros-args -p save_map_timeout:=20.0
```

> **`save_map_timeout` gereklidir.** Varsayılan süre bu stack için yetmez ve
> `map_saver` "Failed to spin map subscription" hatasıyla düşer. Ayrıca
> `map_saver_cli`'ye **`use_sim_time` vermeyin** — sim saatiyle çalıştırılırsa
> aynı hatayla düşer (ikisi de ölçülerek doğrulandı).

`~/mecanum_harita.pgm` ve `~/mecanum_harita.yaml` oluşur.

### 1.6 Kendi haritanızla Nav2

```bash
ros2 launch mecanum_bringup sim_nav.launch.py map:=$HOME/mecanum_harita.yaml
```

> **Koordinat çerçevesine dikkat.** SLAM haritalarında `map` frame'i SLAM'in
> **başladığı** poza oturur: robot o haritada **(0, 0)** noktasındadır. Profil
> haritasında ise `map` frame'i dünya frame'i ile aynıdır. Yani **aynı hedef
> koordinatı iki haritada farklı yerlere denk gelir.**
>
> Kendi SLAM haritanızla hedef verirken koordinatları **spawn noktasına göre**
> düşünün. Dünya koordinatı gönderirseniz hedef harita dışına düşer ve Nav2
> `ABORTED` döndürür (ölçüldü). RViz'de **"2D Goal Pose"** ile tıklayarak hedef
> verirseniz bu sorun oluşmaz — tıkladığınız nokta zaten doğru frame'dedir.

Launch bu ayrımı otomatik hesaba katar. Poz yine de yanlış görünürse
`auto_initial_pose:=false` verip RViz'de **"2D Pose Estimate"** ile elle
düzeltin.

### 1.7 GUI'siz (sunucu / CI) çalıştırma

```bash
ros2 launch mecanum_bringup sim_nav.launch.py headless:=true rviz:=false
```

---

## Yol 2 — Ubuntu 22.04 + Jazzy Docker

Host'ta **Ubuntu 22.04 + Humble kalır**; Jazzy/Harmonic yalnızca konteynerde
çalışır. Host'a Jazzy kurulmaz.

### 2.1 Docker kurulumu (bir kez)

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/mustafaerkam/enro_mecanum_humbletojazzy.git
cd enro_mecanum_humbletojazzy
./scripts/install_docker_host.sh
```

Kurulumdan sonra **yeni bir terminal açın** (docker grup üyeliği için) veya
`newgrp docker` çalıştırın. Doğrulama: `docker run --rm hello-world`.

### 2.2 İmajı oluştur ve derle

```bash
cd ~/enro_mecanum_humbletojazzy
cp .env.example .env          # gerekirse duzenleyin (asagiya bakin)
sed -i "s/^USER_ID=.*/USER_ID=$(id -u)/" .env
sed -i "s/^GROUP_ID=.*/GROUP_ID=$(id -g)/" .env
docker compose build jazzy
docker compose run --rm jazzy ./scripts/build_jazzy.sh
```

Kaynak kod `/workspace` olarak bağlanır; derleme çıktıları host'taki
`build_jazzy/`, `install_jazzy/`, `log_jazzy/` dizinlerine düşer. Humble
çıktıları etkilenmez.

### 2.3 GUI (Gazebo + RViz ekranda)

`.env` içindeki `DISPLAY` **kendi ekranınızla eşleşmelidir**. Kontrol edin:

```bash
echo $DISPLAY          # ornegin :1  (.env.example varsayilani :0'dir)
```

Farklıysa `.env` dosyasında düzeltin. Sonra X11 erişimi verin:

```bash
xhost +local:          # her yeniden baslatmada tekrar gerekir
```

Simülasyonu GUI ile başlatın:

```bash
docker compose run --rm jazzy ros2 launch mecanum_bringup sim_nav.launch.py
```

İşiniz bitince erişimi geri kısıtlayın:

```bash
xhost -local:
```

### 2.4 GUI'siz çalıştırma

```bash
docker compose run --rm jazzy \
  ros2 launch mecanum_bringup sim_nav.launch.py headless:=true rviz:=false
```

### 2.5 Konteynerde teleop / SLAM / harita kaydetme

Simülasyonu **adlandırılmış** bir konteynerde arka planda başlatın:

```bash
docker compose run -d --name enro-sim jazzy \
  ros2 launch mecanum_bringup sim_mapping.launch.py
```

Aynı konteynere ikinci bir kabuk ile bağlanın:

```bash
docker exec -it enro-sim bash -lc \
  'source /opt/ros/jazzy/setup.bash && source /workspace/install_jazzy/setup.bash && \
   ros2 run mecanum_teleop teleop_node'
```

Harita kaydetme (`/workspace` host'taki repo dizinidir):

```bash
docker exec -it enro-sim bash -lc \
  'source /opt/ros/jazzy/setup.bash && source /workspace/install_jazzy/setup.bash && \
   ros2 run nav2_map_server map_saver_cli -f /workspace/mecanum_harita \
     --ros-args -p save_map_timeout:=20.0'
```

Bitince konteyneri kaldırın:

```bash
docker rm -f enro-sim
```

Ayrıntılar: [docs/INSTALL_DEV.md](docs/INSTALL_DEV.md).

---

## Yol 3 — Raspberry Pi 5 gerçek araç

**Önkoşul:** Raspberry Pi 5 üzerinde 64-bit Ubuntu Server 24.04 (`arm64`).
Pi'de Docker gerekmez.

> **GÜVENLİK — önce okuyun:** [docs/SAFETY.md](docs/SAFETY.md).
> Gerçek araç ilk testte **tekerlekleri havada** olmalıdır. Nav2'yi başlatmak
> tek başına hareket üretmez, ancak teker sırası ve yönleri
> doğrulanmadan robotu yere indirmeyin. Fiziksel acil durdurma zorunludur.

### 3.1 Pi'ye native ROS 2 Jazzy kur

Ubuntu 24.04 arm64 kurulumundan sonra Pi üzerinde:

```bash
sudo apt update
sudo apt install -y software-properties-common curl git
sudo add-apt-repository universe

export ROS_APT_SOURCE_VERSION="$(curl -s \
  https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
  | grep -F 'tag_name' | awk -F'"' '{print $4}')"
curl -L -o /tmp/ros2-apt-source.deb \
  "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb

sudo apt update
sudo apt upgrade -y
sudo apt install -y ros-jazzy-ros-base ros-dev-tools
echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc
source /opt/ros/jazzy/setup.bash
```

### 3.2 Repository, bağımlılıklar ve native derleme

```bash
git clone https://github.com/mustafaerkam/enro_mecanum_humbletojazzy.git
cd enro_mecanum_humbletojazzy
./scripts/provision_pi5.sh
```

Betik Ubuntu sürümünü, `aarch64` mimarisini ve Jazzy varlığını kontrol eder;
sonra Nav2, ros2_control, SLAM Toolbox, micro-ROS agent, `rplidar_ros` ve diğer
bağımlılıkları kurup workspace'i native derler. Derlemeden sonra her terminalde:

```bash
source /opt/ros/jazzy/setup.bash
source ~/enro_mecanum_humbletojazzy/install_jazzy/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export ROS_LOCALHOST_ONLY=0
```

### 3.3 USB cihaz adları ve araç kalibrasyonu

LiDAR modeli **RPLIDAR A1M8** olarak yapılandırılmıştır. USB kimlikleri,
motor/encoder yönleri ve gerçek hız limitleri hâlâ araca bağlıdır ve
`CALIBRATION_REQUIRED` olarak işaretlidir. Doldurmadan gerçek sürüş yapmayın:

- [docs/CALIBRATION.md](docs/CALIBRATION.md) — teker sırası/yön doğrulaması
- [config/vehicles/](config/vehicles/) — araç profili
- [config/udev/](config/udev/) — `/dev/mecanum_esp32`, `/dev/mecanum_lidar`
  kararlı cihaz adları

Önce ESP32 ve RPLIDAR'ın gerçek USB kimliklerini bulun:

```bash
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
udevadm info --attribute-walk --name=/dev/ttyUSB0 \
  | grep -E 'idVendor|idProduct|serial'
```

Bulduğunuz değerleri
`config/udev/99-mecanum.rules.example` içindeki ilgili
`CALIBRATION_REQUIRED` alanlarına yazın, ardından:

```bash
sudo cp config/udev/99-mecanum.rules.example \
  /etc/udev/rules.d/99-mecanum.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo usermod -aG dialout "$USER"
ls -l /dev/mecanum_esp32 /dev/mecanum_lidar
```

Grup değişikliğinden sonra oturumu kapatıp yeniden açın. Her iki kararlı cihaz
yolu oluşmadan gerçek stack'i başlatmayın.

### 3.4 Çalıştırma sırası

Her adım **ayrı terminalde**:

```bash
# 1) micro-ROS agent (ESP32 baglantisi)
#    Baud firmware ile ESLESMELIDIR; repo geneli 921600 varsayar
#    (config/vehicles/reference_mecanum.yaml -> micro_ros_baud).
ros2 run micro_ros_agent micro_ros_agent serial --dev /dev/mecanum_esp32 -b 921600

# 2) RPLIDAR A1M8 (/dev/mecanum_lidar, 115200 baud, frame: lidar_link)
ros2 launch mecanum_bringup rplidar_a1.launch.py

# 3) Gercek arac kontrol katmani + SLAM
ros2 launch mecanum_bringup real_mapping.launch.py transport:=micro_ros

#    ya da kayitli haritayla navigasyon
ros2 launch mecanum_bringup real_nav.launch.py transport:=micro_ros \
  map:=$HOME/harita.yaml
```

Stack'i başlatmadan önce veri sözleşmesini doğrulayın:

```bash
ros2 topic hz /wheel/states
ros2 topic hz /scan
ros2 topic hz /imu/data_raw
ros2 topic echo /scan --once --field header   # frame_id: lidar_link
```

Mapping sırasında haritayı ayrı terminalde kaydedin:

```bash
ros2 run nav2_map_server map_saver_cli -f "$HOME/harita" \
  --ros-args -p save_map_timeout:=20.0
```

Gerçek araç launch dosyaları RViz'i otomatik açmaz. Operatör bilgisayarında
aynı `ROS_DOMAIN_ID=42` ve aynı ağ erişimiyle ya da Pi'nin masaüstünde:

```bash
ros2 launch mecanum_bringup rviz.launch.py use_sim_time:=false
```

`real_nav.launch.py` **otomatik başlangıç pozu vermez**; RViz'de
**"2D Pose Estimate"** ile poz vermeniz gerekir. Bu kasıtlıdır — gerçek robotta
bilinen bir spawn pozu yoktur.

Donanımsız arayüz kontrolü için `transport:=mock` kullanılabilir; bu
**gerçek hareket kanıtı değildir**.

```bash
ros2 launch mecanum_bringup real_nav.launch.py transport:=mock
ros2 launch mecanum_bringup real_mapping.launch.py transport:=mock
```

Bu iki mock profili de aynı anda değil, sırayla çalıştırılmalıdır.

### 3.5 ESP32 firmware sözleşmesi

Firmware bu repository'de bulunmaz. Gerçek aracın çalışması için ESP32
micro-ROS firmware'i aşağıdaki sözleşmeyi sağlamalıdır:

| Yön | Topic | Tip | İçerik |
|---|---|---|---|
| Pi → ESP32 | `wheel/commands` | `std_msgs/msg/Float32MultiArray` | `[FL, FR, RL, RR]`, hedef hızlar `rad/s` |
| ESP32 → Pi | `wheel/states` | `std_msgs/msg/Float32MultiArray` | 8 değer: 4 kümülatif konum `rad` + 4 hız `rad/s` |
| ESP32 → Pi | `imu/data_raw` | `sensor_msgs/msg/Imu` | SI birimleri, `frame_id=imu_link` |

Komut ve feedback nominal **50 Hz**, QoS `best_effort / KeepLast(1)` olmalıdır.
Firmware, `wheel/commands` kesildiğinde **en geç 200 ms içinde motorları
durduran bağımsız bir watchdog** içermelidir. ROS tarafındaki timeout bu
watchdog'un yerini tutmaz. Teker sırası her yerde `[FL, FR, RL, RR]` kalır.

İlk motor testi robot havadayken tek tek yapılmalıdır:

```bash
ros2 topic echo /wheel/states --once    # tam 8 eleman beklenir
ros2 topic pub --once /wheel/commands std_msgs/msg/Float32MultiArray \
  "{data: [1.0, 0.0, 0.0, 0.0]}"
```

Ön-sol teker düşük hızda dönmeli ve ilgili encoder konumu artmalıdır. Sonra
diğer üç teker, ileri/geri, iki yanal yön, iki dönüş yönü ve agent kesilerek
watchdog sırasıyla doğrulanmalıdır.

Ayrıntılar: [docs/INSTALL_PI5.md](docs/INSTALL_PI5.md) ·
[docs/LOW_LEVEL_INTERFACE.md](docs/LOW_LEVEL_INTERFACE.md)

---

## Mimari özeti

```text
Nav2 / teleop
   -> twist_mux          (cmd_vel_nav | cmd_vel_teleop -> cmd_vel_selected)
   -> velocity_smoother  (-> cmd_vel_smoothed)
   -> collision_monitor  (-> cmd_vel)
   -> mecanum_drive_controller
   -> ros2_control -> 4 teker

wheel/odometry + imu/data_raw -> EKF -> odometry/filtered
```

Komut zinciri **uçtan uca `geometry_msgs/msg/TwistStamped`** kullanır. Jazzy'de
`twist_mux` `TwistStamped` dinler; zincirde tek bir `Twist` kalırsa komut
controller'a **hiç ulaşmaz**. Zincirin hiçbir yolu (teleop dahil) güvenlik
katmanlarını **bypass edemez**.

Ayrıntı: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Test ve doğrulama

```bash
./scripts/test_jazzy.sh            # birim testler + statik sozlesme denetimi
./scripts/smoke_jazzy.sh nav       # gercek headless sim: Nav2 profili
./scripts/smoke_jazzy.sh mapping   # gercek headless sim: SLAM + harita kaydetme
./scripts/smoke_real_mock.sh nav   # gercek launch agaci, donanimsiz mock
./scripts/smoke_real_mock.sh mapping
```

## Lisans ve bakım

Maintainer: **Mustafa Erkam** (`hekimhanerkam@gmail.com`). Bu kaynak kod
`Proprietary` olarak yayımlanır; kullanım ve dağıtım için maintainer'dan yazılı
izin gerekir. Ayrıntı: [LICENSE](LICENSE).

Docker'da:

```bash
docker compose run --rm jazzy ./scripts/test_jazzy.sh
docker compose run --rm jazzy ./scripts/smoke_jazzy.sh nav
```

Smoke testleri gerçek bir simülasyon açar; statik testlerin yakalayamadığı
çalışma zamanı hatalarını (friction frame, lifecycle, mesaj tipi uyuşmazlığı)
yakalar. `smoke_jazzy.sh nav`, güvenli komut zinciri üzerinden ileri/geri,
sağ/sol strafe, iki dönüş yönü ve gerçek `NavigateToPose=SUCCEEDED` kabulünü de
denetler.

## Sık karşılaşılan sorunlar

| Belirti | Kontrol / çözüm |
|---|---|
| `Package 'mecanum_bringup' not found` | Önce build edin, sonra `source install_jazzy/setup.bash` çalıştırın. |
| Docker izni reddediliyor | Oturumu yeniden açın veya `newgrp docker` çalıştırın. |
| Gazebo/RViz penceresi açılmıyor | `.env` içindeki `DISPLAY` ile `echo $DISPLAY` eşleşmeli; önce `xhost +local:` çalıştırın, bitince `xhost -local:` yapın. |
| Teleop `Inappropriate ioctl for device` | Launch kullanmayın; interaktif terminalde `ros2 run mecanum_teleop teleop_node` çalıştırın. |
| Gerçek controller active olmuyor | `/wheel/states`, agent baud'u, topic adı ve 8 elemanlı feedback sözleşmesini kontrol edin. |
| RPLIDAR açılamıyor | `/dev/mecanum_lidar` udev yolunu, `dialout` üyeliğini ve 115200 baud'u kontrol edin. |
| Nav2 robotu hareket ettirmiyor | Başlangıç pozunu, lifecycle durumlarını, `/scan`, `/odometry/filtered` ve `/cmd_vel` zincirini kontrol edin. |

## Belgeler

| Belge | İçerik |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Düğümler, topic'ler, TF ağacı |
| [INSTALL_DEV.md](docs/INSTALL_DEV.md) | Docker geliştirme ortamı ayrıntıları |
| [INSTALL_PI5.md](docs/INSTALL_PI5.md) | Pi 5 native kurulum |
| [LOW_LEVEL_INTERFACE.md](docs/LOW_LEVEL_INTERFACE.md) | Firmware'in sağlaması gereken sözleşme |
| [SAFETY.md](docs/SAFETY.md) | Gerçek araç güvenlik kuralları |
| [CALIBRATION.md](docs/CALIBRATION.md) | Teker sırası/yön doğrulaması |
| [NEW_VEHICLE.md](docs/NEW_VEHICLE.md) | Yeni araç profili ekleme |
| [COMPATIBILITY.md](docs/COMPATIBILITY.md) | Doğrulanmış sürümler ve test sonuçları |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Sık karşılaşılan hatalar ve kök nedenleri |
| [BASELINE.md](docs/BASELINE.md) | Port öncesi Humble davranışı |

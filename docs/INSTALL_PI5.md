# Raspberry Pi 5 — high-level kurulum

Hedef: **Pi 5, arm64, Ubuntu 24.04, native ROS 2 Jazzy.** Pi'de Docker
gerekmez.

Bu belge **high-level** ROS stack'ini kurar. Firmware (ESP32) bu repository'de
değildir; beklenen arayüz [LOW_LEVEL_INTERFACE.md](LOW_LEVEL_INTERFACE.md)
içinde tanımlıdır.

> **Önce [SAFETY.md](SAFETY.md) okuyun.** İlk testte robot **tekerleri havada**
> olmalıdır.

---

## 1. Ortamı doğrula ve derle

```bash
git clone https://github.com/mustafaerkam/enro_mecanum_humbletojazzy.git
cd enro_mecanum_humbletojazzy
./scripts/provision_pi5.sh
```

Betik şunları yapar:

1. `arm64` mimarisini doğrular (değilse durur)
2. Ubuntu **24.04** olduğunu doğrular (değilse durur)
3. `/opt/ros/jazzy` varlığını doğrular (değilse durur)
4. High-level bağımlılıkları kurar: `navigation2`, `nav2_bringup`,
   `robot_localization`, `ros2_control`, `ros2_controllers`, `slam_toolbox`,
   `twist_mux`, `micro_ros_agent`, `rplidar_ros`, `xacro`
5. `rosdep install` çalıştırır — **Gazebo paketleri atlanır**
   (`gz_ros2_control`, `ros_gz_bridge`, `ros_gz_sim`): gerçek araçta
   simülasyon gerekmez
6. `install_jazzy/` dizinine native derler

Sonra:

```bash
source /opt/ros/jazzy/setup.bash
source install_jazzy/setup.bash
```

## 2. Kararlı cihaz adları (udev)

USB cihaz sırasına (`/dev/ttyUSB0`) **güvenmeyin**; her açılışta değişebilir.

Kimlikleri bulun:

```bash
udevadm info --attribute-walk --name=/dev/ttyUSB0 | grep -E "idVendor|idProduct|serial"
```

`config/udev/99-mecanum.rules.example` dosyasını kopyalayıp içindeki
`CALIBRATION_REQUIRED` değerlerini **kendi donanımınızın** değerleriyle
doldurun:

```bash
sudo cp config/udev/99-mecanum.rules.example /etc/udev/rules.d/99-mecanum.rules
sudo nano /etc/udev/rules.d/99-mecanum.rules      # placeholder'lari doldurun
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Doğrulayın:

```bash
ls -l /dev/mecanum_esp32 /dev/mecanum_lidar
```

> Placeholder'lar dolu değilken bu dosyayı kurmayın — kural eşleşmez.

## 3. Ortam değişkenleri

```bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export ROS_LOCALHOST_ONLY=0        # RViz'i baska makineden kullanacaksaniz
```

## 4. Çalıştırma sırası

Her adım **ayrı terminalde**.

### 4.1 micro-ROS agent

```bash
ros2 run micro_ros_agent micro_ros_agent serial --dev /dev/mecanum_esp32 -b 921600
```

> Baud **firmware ile eşleşmelidir**. Repo geneli 921600 varsayar
> (`config/vehicles/reference_mecanum.yaml` → `micro_ros_baud`). Firmware'iniz
> farklıysa profil dosyasını da güncelleyin.

Bağlantıyı doğrulayın:

```bash
ros2 topic hz /wheel/states        # firmware feedback yayinliyor mu
```

### 4.2 LiDAR sürücüsü

Araçtaki LiDAR **RPLIDAR A1M8**'dir. Repo, Jazzy `rplidar_ros` düğümünü
`/dev/mecanum_lidar`, **115200 baud**, `lidar_link` frame'i ve `Sensitivity`
tarama modu ile başlatan bir launch dosyası sağlar:

```bash
ros2 launch mecanum_bringup rplidar_a1.launch.py
```

Başka terminalde doğrulayın:

```bash
ros2 topic hz /scan
ros2 topic echo /scan --once --field header
```

USB cihazı `/dev/mecanum_lidar` olarak görünmüyorsa önce Bölüm 2'deki udev
kuralını kendi adaptörünüzün vendor/product/serial değerleriyle tamamlayın.

### 4.3 Donanımsız arayüz kontrolü (opsiyonel)

Firmware hazır değilken stack'in ayağa kalktığını görmek için:

```bash
ros2 launch mecanum_bringup real_nav.launch.py transport:=mock
```

> Bu **gerçek hareket kanıtı değildir**; yalnızca interface/lifecycle
> kontrolüdür.

### 4.4 Gerçek araç: SLAM veya navigasyon

[SAFETY.md](SAFETY.md) ve [CALIBRATION.md](CALIBRATION.md) tamamlandıktan
sonra:

```bash
# harita cikarma
ros2 launch mecanum_bringup real_mapping.launch.py transport:=micro_ros

# haritayi kaydet (ayri terminal)
ros2 run nav2_map_server map_saver_cli -f $HOME/harita \
  --ros-args -p save_map_timeout:=20.0

# kayitli haritayla navigasyon
ros2 launch mecanum_bringup real_nav.launch.py transport:=micro_ros \
  map:=$HOME/harita.yaml
```

`real_mapping` ve `real_nav` **aynı anda çalıştırılamaz**; ikisi de
`map -> odom` yayınlar.

> `real_nav.launch.py` **otomatik başlangıç pozu vermez.** RViz'de
> **"2D Pose Estimate"** ile poz verin. Bu kasıtlıdır: gerçek robotta bilinen
> bir spawn pozu yoktur.

## 5. Doğrulama kontrol listesi

| Kontrol | Komut |
|---|---|
| Firmware feedback | `ros2 topic hz /wheel/states` |
| LiDAR | `ros2 topic hz /scan` |
| IMU | `ros2 topic hz /imu/data_raw` |
| Controller'lar active | `ros2 control list_controllers` |
| Füzyon odometrisi | `ros2 topic hz /odometry/filtered` |
| TF ağacı | `ros2 run tf2_tools view_frames` |

## 6. Otomatik başlatma (opsiyonel)

`config/systemd/mecanum-micro-ros-agent.service.example` micro-ROS agent'ı
açılışta başlatmak için örnektir. Cihaz yolunu ve baud'u doğruladıktan sonra:

```bash
sudo cp config/systemd/mecanum-micro-ros-agent.service.example \
        /etc/systemd/system/mecanum-micro-ros-agent.service
sudo nano /etc/systemd/system/mecanum-micro-ros-agent.service
sudo systemctl daemon-reload
sudo systemctl enable --now mecanum-micro-ros-agent
```

> Önce **manuel** akışın çalıştığını doğrulayın. Otomatik başlatmayı, ne
> yaptığını bilmeden etkinleştirmeyin — robot açılışta beklenmedik durumda
> olabilir.

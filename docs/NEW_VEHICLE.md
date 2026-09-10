# Yeni araç profili ekleme

Amaç: yeni bir mecanum platformu için **kaynak kodu fork'lamak yerine** bir
profil eklemek.

> **Mevcut durum (dürüst sınır):** Araç profili
> (`config/vehicles/reference_mecanum.yaml`) şu anda **kayıt ve referans
> belgesidir**; Xacro/YAML değerlerini otomatik **beslemez**. Geometri
> değişikliğini aşağıdaki dosyalarda **elle** ve **birlikte** yapmanız gerekir.
> Tek kaynağa indirgeme TODO'dur ([COMPATIBILITY.md](COMPATIBILITY.md)).

---

## 1. Profili kopyalayın

```bash
cp config/vehicles/reference_mecanum.yaml config/vehicles/<arac_adi>.yaml
```

`vehicle_id` alanını güncelleyin. Bilinmeyen donanım değerlerini **tahmin
etmeyin**; `CALIBRATION_REQUIRED` olarak bırakın.

## 2. Geometriyi birlikte güncelleyin

Geometri değişirse **hepsi** güncellenmelidir:

| Dosya | Ne |
|---|---|
| `src/mecanum_robot_description/urdf/mecanum_robot.xacro` | `wheel_radius`, `wheel_offset_x`, `wheel_offset_y` |
| `src/mecanum_control/config/mecanum_controllers.yaml` | `sum_of_robot_center_projection_on_X_Y_axis` (= offset_x + offset_y) |
| `src/mecanum_control/config/mecanum_controllers_sim.yaml` | aynı değer |
| `src/mecanum_navigation/params/nav2_params.yaml` | `robot_radius` / footprint, Collision Monitor poligonları |
| `config/vehicles/<arac_adi>.yaml` | kayıt |

Sim dünyasında spawn boşluğunu da kontrol edin (robot duvara girmemeli).

Tutarlılığı denetleyin:

```bash
./scripts/test_jazzy.sh        # contract_audit lx+ly tutarliligini kontrol eder
```

## 3. Değişmeyenler

Bunlar platformdan bağımsızdır ve **korunur**:

- Joint adları: `wheel_fl_joint`, `wheel_fr_joint`, `wheel_rl_joint`,
  `wheel_rr_joint`
- Low-level dizi sırası: **`[FL, FR, RL, RR]`**
- Topic sözleşmesi: `wheel/commands`, `wheel/states`, `/scan`,
  `/imu/data_raw`
- Frame adları: `base_footprint`, `base_link`, `odom`, `map`, `lidar_link`,
  `imu_link`
- Komut zinciri mesaj tipi: `TwistStamped`

## 4. Sensörler

Sensör sürücüsü çekirdek navigasyona **gömülmez**. Yeni LiDAR/IMU yalnızca
sözleşmeyi sağlamalıdır:

- `/scan` → `sensor_msgs/msg/LaserScan`, `frame_id = lidar_link`
- `/imu/data_raw` → `sensor_msgs/msg/Imu`, `frame_id = imu_link`

Frame adı uyuşmuyorsa **sürücünün** frame parametresini düzeltin, URDF'yi
değil.

Simülasyon LiDAR'ı Xacro'da tanımlıdır (10 Hz, 640 örnek, 0.12–12.0 m); gerçek
LiDAR'ınız farklıysa profil dosyasına kaydedin.

## 5. Kalibrasyon ve ilk test

Yeni araçta **her zaman** sıfırdan kalibrasyon yapın:

1. [CALIBRATION.md](CALIBRATION.md) — geometri, teker sırası, işaretler
2. [SAFETY.md](SAFETY.md) — havada test sırası
3. Ancak sonra yere indirin

`CALIBRATION_REQUIRED` alanları doluyken gerçek motor testi yapmayın.

# Kalibrasyon

Gerçek araç değerleri bu repository'de **bilinmiyor** ve
`CALIBRATION_REQUIRED` olarak işaretlidir. Bu belge onları nasıl ölçüp
gireceğinizi anlatır.

> Kalibrasyon tamamlanmadan robotu yere indirmeyin ([SAFETY.md](SAFETY.md)).

---

## 1. Geometri

Yük altındaki **etkin** değerleri ölçün (boştaki nominal değil):

| Değer | Şu anki | Nerede |
|---|---|---|
| Teker yarıçapı | `0.1625 m` | `mecanum_robot.xacro` → `wheel_radius` |
| Teker offset X | `0.40 m` | `mecanum_robot.xacro` → `wheel_offset_x` |
| Teker offset Y | `0.54 m` | `mecanum_robot.xacro` → `wheel_offset_y` |
| Wheelbase (2·offset X) | `0.80 m` | `config/vehicles/…` → `geometry.wheelbase_m` |
| Wheel separation (2·offset Y) | `1.08 m` | `config/vehicles/…` → `geometry.wheel_separation_m` |
| `lx + ly` | `0.94` | controller YAML → `sum_of_robot_center_projection_on_X_Y_axis` |

`lx + ly` değeri `wheel_offset_x + wheel_offset_y` ile **tutarlı olmalıdır**
(0.40 + 0.54 = 0.94). Geometriyi değiştirirseniz bu türetilmiş değeri de
güncelleyin — statik denetim (`contract_audit`) bu tutarlılığı kontrol eder.

Geometri değişince **birlikte** güncellenmesi gerekenler:

- `mecanum_robot.xacro`
- `mecanum_controllers.yaml` **ve** `mecanum_controllers_sim.yaml`
- Nav2 footprint ve Collision Monitor poligonları
- `config/vehicles/<araç>.yaml`

## 2. Teker sırası ve yönler

Dizi sırası her katmanda **`[FL, FR, RL, RR]`**'dir.

**Robot havadayken**, her tekeri **tek tek** düşük pozitif hızla sürün:

```bash
ros2 topic pub --once /wheel/commands std_msgs/msg/Float32MultiArray \
  "{data: [1.0, 0.0, 0.0, 0.0]}"     # yalniz FL
```

Her teker için kaydedin:

1. Hangi fiziksel teker döndü? → **sıra** doğrulaması
2. Fiziksel dönüş yönü ileri mi? → **motor işareti**
3. Encoder değeri **arttı** mı? → **encoder işareti**

```bash
ros2 topic echo /wheel/states --once
```

Yanlış olan varsa işareti **firmware'de tek bir yerde** düzeltin. Aynı işareti
hem firmware'de hem high-level'da düzeltmeye çalışmayın — iki kez ters çevirme
hatası buradan çıkar. Sonucu `config/vehicles/<araç>.yaml` içindeki
`drivetrain.motor_sign` / `drivetrain.encoder_sign` alanlarına (şu an
`CALIBRATION_REQUIRED`) **kayıt** olarak yazın.

Sonra bileşik desenleri doğrulayın: saf `vx`, saf `vy`, saf `wz`.

## 3. IMU ve LiDAR

- **IMU montaj dönüşü** (`sensors.imu_mount_pose`, şu an
  `CALIBRATION_REQUIRED`): ölçüp `mecanum_robot.xacro` içindeki `imu_link`
  origin'ine girin. Robot düz dururken `imu/data_raw` ivmesi ~`(0, 0, +9.8)`
  olmalıdır.
- **LiDAR pozu**: düz bir duvara bakarken `/scan` verisinin duvarı düz
  görmesi gerekir. `frame_id` **`lidar_link`** olmalıdır; farklıysa
  **sürücünün** frame parametresini düzeltin, URDF'yi değil.

## 4. Hız limitleri ve fren mesafesi

`config/vehicles/reference_mecanum.yaml` içindeki limitler
**`CALIBRATION_REQUIRED`**'dır:

```yaml
limits:
  configured_linear_x_m_s: 0.5          # stack'te YAPILANDIRILMIS deger
  configured_linear_y_m_s: 0.5
  configured_angular_z_rad_s: 1.2
  command_timeout_ms: 500
  validated_real_vehicle_limits: CALIBRATION_REQUIRED
```

> `configured_*` değerleri stack'in **şu anda kullandığı** limitlerdir; gerçek
> araçta güvenli oldukları **doğrulanmamıştır**. Ölçtükten sonra
> `validated_real_vehicle_limits` alanını doldurun.

Fren mesafesini **düşük hızdan başlayarak** kademeli ölçün: robotu sabit hızda
sürüp komutu kesin, durana kadarki mesafeyi kaydedin. Ölçülen mesafeye göre:

- Collision Monitor `PolygonStop` boyutu fren mesafesinden **büyük** olmalı
- `PolygonSlow` ondan da büyük olmalı
- `velocity_smoother` ivme limitleri gerçek motor kapasitesini aşmamalı

## 5. Simülasyon notu

Simülasyondaki değerler **gerçek araç kalibrasyonu değildir**. Sim'de ölçülen
yanal izleme kaybı (~%16) mecanum makara temas modelinin bir özelliğidir;
gerçek araca taşınmaz.

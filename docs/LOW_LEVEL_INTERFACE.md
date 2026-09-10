# Low-level arayüz sözleşmesi

**Firmware bu repository'de yoktur.** Bu belge, high-level ROS stack'inin
firmware'den (ESP32) ne beklediğini tanımlar. Firmware'i geliştirecek kişi bu
sözleşmeyi sağlamalıdır.

Bu sözleşme **yalnızca gerçek araç** içindir. Simülasyon ESP32, seri port ve
micro-ROS agent olmadan bağımsız çalışır.

---

## Topic'ler

| Yön | Topic | Tip | İçerik |
|---|---|---|---|
| Pi → ESP32 | `wheel/commands` | `std_msgs/msg/Float32MultiArray` | 4 eleman: `[FL, FR, RL, RR]` hedef hız, **`rad/s`** |
| ESP32 → Pi | `wheel/states` | `std_msgs/msg/Float32MultiArray` | **8 eleman**: ilk 4 kümülatif konum (`rad`), son 4 hız (`rad/s`) |
| ESP32 → Pi | `imu/data_raw` | `sensor_msgs/msg/Imu` | SI birimleri, `frame_id = imu_link` |

### Dizi sırası

Her iki dizide de sıra **`[FL, FR, RL, RR]`**'dir (ön-sol, ön-sağ, arka-sol,
arka-sağ). Bu sıra high-level'ın her katmanında aynıdır ve
**değiştirilmemelidir**.

`wheel/states` dizisi **8 elemanlıdır**:

```text
index:  0    1    2    3     4    5    6    7
      pFL  pFR  pRL  pRR   vFL  vFR  vRL  vRR
      └── konum (rad) ──┘   └── hiz (rad/s) ──┘
```

Konum **kümülatif** olmalıdır (her turda sıfırlanmamalı); high-level odometri
bu değerin sürekliliğine dayanır.

## Zamanlama ve QoS

| Parametre | Değer | Not |
|---|---|---|
| Nominal kontrol/feedback hızı | **50 Hz** | |
| QoS | `best_effort`, `KeepLast(1)` | `mecanum_system_interface.cpp` |
| Feedback bayatlık eşiği | **0.2 s** (`state_timeout`) | Bu süreden eski feedback **bayat** sayılır |
| İlk feedback bekleme | **5.0 s** (`activation_timeout`) | `on_activate` bu kadar bekler |
| Controller komut zaman aşımı | **0.5 s** (`reference_timeout`) | |

Feedback bayatlarsa veya hiç gelmezse durum **anlaşılır biçimde raporlanır**;
high-level sessizce eski değerle devam etmez.

## micro-ROS agent

```bash
ros2 run micro_ros_agent micro_ros_agent serial --dev /dev/mecanum_esp32 -b 921600
```

Baud **firmware ile eşleşmelidir**. Repo geneli **921600** varsayar
(`config/vehicles/reference_mecanum.yaml` → `devices.micro_ros_baud`).
Firmware'iniz farklı bir değer kullanıyorsa profil dosyasını da güncelleyin.

`/dev/mecanum_esp32` udev ile sabitlenmiş kararlı addır
([INSTALL_PI5.md](INSTALL_PI5.md)).

## Firmware'in sağlaması gereken minimum davranış

1. **Watchdog (zorunlu).** `wheel/commands` kesildiğinde firmware, **200 ms
   veya daha kısa** sürede tüm motorları durdurmalıdır. Son komutu süresiz
   tutmak **kabul edilemez**.

   > ROS tarafındaki zaman aşımları bunun yerine geçmez: micro-ROS bağlantısı
   > koparsa ROS katmanı motorlara ulaşamaz. Durdurma **firmware'in**
   > sorumluluğudur.

2. **Birim dönüşümü.** `rad/s` ↔ motor PWM/RPM ve encoder tick ↔ `rad`
   dönüşümleri firmware'de yapılır. High-level yalnızca `rad` ve `rad/s`
   bilir.

3. **İşaret tutarlılığı.** Motor ve encoder işaretleri **firmware'de tek bir
   yerde** düzeltilmelidir ([CALIBRATION.md](CALIBRATION.md)). Aynı işareti
   hem firmware'de hem high-level'da ters çevirmek çift-negatif hatasına yol
   açar.

4. **Motor güvenliği.** Akım/sıcaklık koruması, PID ve motor sürücü
   güvenliği firmware sorumluluğundadır.

## Doğrulama

```bash
# firmware feedback geliyor mu
ros2 topic hz /wheel/states
ros2 topic echo /wheel/states --once        # 8 eleman olmali

# IMU
ros2 topic hz /imu/data_raw

# tek teker testi (robot HAVADA)
ros2 topic pub --once /wheel/commands std_msgs/msg/Float32MultiArray \
  "{data: [1.0, 0.0, 0.0, 0.0]}"
```

## Gelecek için not (port kapsamı dışı)

Mevcut `Float32MultiArray` arayüzü bu port için **yeterlidir**. İleride
tip güvenliği ve alan adlandırması için custom message tanımlanabilir
(örn. `WheelCommand` / `WheelState`), ancak bu **ana portu geciktirmemelidir**
ve firmware tarafıyla birlikte planlanmalıdır.

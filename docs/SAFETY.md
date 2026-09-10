# Gerçek araç güvenliği

Bu belge **high-level** stack'in sağladığı ve **sağlamadığı** güvenlik
davranışlarını tanımlar. Kapsamlı bir safety state machine veya firmware
güvenlik kodu bu repository'de **yoktur**.

---

## İlk test öncesi zorunlu koşullar

1. **Tekerler zeminden kesik olmalı.** Robot ilk testte havada (sehpa/takoz
   üzerinde) olmalıdır.
2. **Fiziksel acil durdurma erişilebilir olmalı.** Yazılım katmanları bunun
   yerine geçmez.
3. **Firmware watchdog çalışıyor olmalı.** Komut kesildiğinde motorlar
   durmalıdır ([LOW_LEVEL_INTERFACE.md](LOW_LEVEL_INTERFACE.md)).
4. **Kalibrasyon tamamlanmış olmalı.** Teker sırası, motor yönleri, encoder
   işaretleri ([CALIBRATION.md](CALIBRATION.md)).

`CALIBRATION_REQUIRED` alanları doluyken gerçek sürüş yapmayın.

## High-level stack'in sağladıkları

| Davranış | Nasıl |
|---|---|
| Launch başlangıçta **sıfır hız** üretir | Hiçbir düğüm kendiliğinden komut yayınlamaz |
| Nav2'nin başlatılması **tek başına hareket üretmez** | Hareket için açık bir hedef (goal) gerekir |
| Komut zaman aşımı | `mecanum_drive_controller` `reference_timeout: 0.5` s içinde komut gelmezse sıfırlar |
| Deaktivasyonda sıfır komut | `MecanumSystemInterface::on_deactivate` dört tekere de 0.0 yazar |
| Güvenlik zinciri **bypass edilemez** | Teleop dahil her yol smoother + collision monitor'den geçer |
| `real_nav` otomatik poz vermez | Başlangıç pozu elle verilir; yanlış pozla otonom hareket önlenir |

## High-level stack'in sağlamadıkları

Bunlar **firmware ve donanım sorumluluğundadır**:

- Motor akım/sıcaklık koruması
- Komut watchdog'unun **kendisi** (ROS tarafı watchdog'un yerine geçmez)
- Fiziksel acil durdurma
- Encoder arıza tespiti
- Pil/gerilim koruması

> ROS tarafındaki zaman aşımları **yardımcıdır**, güvenlik sertifikasyonu
> değildir. micro-ROS bağlantısı koparsa ROS katmanı motorları durduramaz —
> bunu firmware watchdog'u yapmalıdır.

## İlk hareket testi sırası

Robot **havadayken**, düşük hız limitleriyle, her adımı tek tek:

1. **Tek teker testi.** Her tekeri ayrı ayrı düşük pozitif hızla sürün.
   Fiziksel dönüş yönünü ve encoder işaretinin **arttığını** doğrulayın.
   Yanlışsa işareti **firmware'de tek yerde** düzeltin
   ([CALIBRATION.md](CALIBRATION.md)).
2. **Saf ileri (`vx > 0`).** Dört teker aynı yönde dönmeli.
3. **Saf geri (`vx < 0`).**
4. **Yanal, iki yön (`vy`).** Mecanum çapraz deseni doğru olmalı.
5. **Dönüş, iki yön (`wz`).**
6. **Feedback kaybı testi.** micro-ROS agent'ı durdurun; motorların **firmware
   watchdog** ile durduğunu doğrulayın.

Her adım beklendiği gibi çalışmadan bir sonrakine geçmeyin.

## Robotu yere indirmeden önce

- Yukarıdaki altı adım **havada** geçmiş olmalı
- Hız limitleri düşük tutulmalı
- Fren mesafesi ölçülüp Collision Monitor poligonları güncellenmiş olmalı
  ([CALIBRATION.md](CALIBRATION.md))
- Acil durdurmaya ulaşabilecek bir kişi başında olmalı

## Nav2 ve otonom hareket

Nav2 stack'inin **active** olması hareket demek değildir. Hareket yalnızca bir
hedef gönderildiğinde başlar. Buna rağmen:

- İlk otonom testi **geniş, boş** bir alanda yapın
- Başlangıç pozunu RViz'de doğru verin — yanlış poz, robotun haritada olmayan
  bir yere gitmeye çalışmasına yol açar
- Collision Monitor'ün `stop` bölgesi robotu **kilitleyebilir**: durma
  komutunun yön bilgisi yoktur, duvara yakınken kaçış komutu da sıfırlanır.
  Mapping oturumunda bu yüzden `stop_polygon_enabled` varsayılan olarak
  kapalıdır; Nav2 oturumunda **açıktır**.

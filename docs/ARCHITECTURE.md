# Mimari

Sim ve gerçek araç **aynı** ROS topic, controller ve TF sözleşmesini kullanır;
yalnızca `ros2_control` hardware plugin'i değişir. Bu, simülasyonda doğrulanan
akışın gerçek araçta da aynı isimlerle çalışmasını sağlar.

## Veri akışı

```text
                    ┌─ teleop  ──> cmd_vel_teleop ─┐
                    │                              │
Nav2 controller_server ──> cmd_vel_nav ────────────┤
                                                   v
                                              twist_mux
                                                   │  cmd_vel_selected
                                                   v
                                          velocity_smoother
                                                   │  cmd_vel_smoothed
                                                   v
                                          collision_monitor
                                                   │  cmd_vel
                                                   v
                                    mecanum_drive_controller
                                                   │
                                                   v
                             ros2_control hardware interface
                             (sim: gz_ros2_control | gerçek: MecanumSystemInterface)
                                                   │
                                                   v
                                          FL   FR   RL   RR

wheel/odometry + imu/data_raw ──> EKF ──> odometry/filtered ──> odom TF
scan ──> slam_toolbox (mapping)  |  AMCL (navigation)
```

**Güvenlik zinciri bypass edilemez.** Teleop dahil hiçbir komut yolu
`velocity_smoother` ve `collision_monitor` katmanlarını atlamaz.

## Mesaj tipi sözleşmesi — TwistStamped

Komut zinciri **uçtan uca `geometry_msgs/msg/TwistStamped`** kullanır:

| Topic | Tip |
|---|---|
| `/cmd_vel_teleop` | `TwistStamped` |
| `/cmd_vel_nav` | `TwistStamped` |
| `/cmd_vel_selected` | `TwistStamped` |
| `/cmd_vel_smoothed` | `TwistStamped` |
| `/cmd_vel` | `TwistStamped` |

Jazzy'de `twist_mux` `TwistStamped` dinler. Zincirde tek bir `Twist` kalırsa
aynı topic üzerinde iki mesaj tipi oluşur ve komut controller'a **hiç ulaşmaz**
(port sırasında bir kez yaşandı). Bunu sağlamak için Nav2 tarafında
`enable_stamped_cmd_vel: true` verilir: `controller_server`, `behavior_server`,
`velocity_smoother`, `collision_monitor`.

`./scripts/smoke_jazzy.sh` bu sözleşmeyi her çalıştırmada denetler.

## TF ağacı ve tek-sahip kuralı

```text
map ──> odom ──> base_footprint ──> base_link ──> imu_link
                                              ├─> lidar_link
                                              ├─> wheel_fl
                                              ├─> wheel_fr
                                              ├─> wheel_rl
                                              └─> wheel_rr
```

Her TF'in **tek** sahibi vardır:

| Transform | Sahibi |
|---|---|
| `map -> odom` | `slam_toolbox` (mapping) **veya** `amcl` (navigation) — asla ikisi birden |
| `odom -> base_footprint` | `ekf_filter_node` (robot_localization) |
| `base_footprint` altı | `robot_state_publisher` (statik, URDF'ten) |

`sim_nav` ve `sim_mapping` profilleri bu yüzden **aynı anda çalıştırılamaz**;
ikisi de `map -> odom` yayınlar. Bringup katmanı ikisinin birlikte include
edilmemesini garanti eder.

Gazebo'nun `MecanumDrive` plugin'i **kullanılmaz**: aynı joint'leri ikinci kez
sürer ve ikinci bir odometry/TF sahibi oluştururdu. Hareketin tek sahibi
`ros2_control`'dür.

## Controller lifecycle sırası

1. `robot_state_publisher` → `/robot_description` yayınlar
2. `controller_manager` bu **topic'ten** URDF alır (Jazzy: parametre değil topic)
3. `joint_state_broadcaster` configure → activate
4. `mecanum_drive_controller` configure → activate

Spawner'lara controller parametreleri Jazzy'de `--param-file` ile geçirilir.

## Simülasyon ayrıntıları

`gz_ros2_control` controller manager'ı **model içinde** oluşturur:

- Plugin: `libgz_ros2_control-system.so`
- Sınıf: `gz_ros2_control::GazeboSimROS2ControlPlugin`

Gazebo'dan ROS'a yalnızca şunlar bridge edilir: `/clock`, `/scan`,
`/imu/data_raw` ve **yalnız test amaçlı** `/ground_truth/odom`.

> `/ground_truth/odom` **üretim girdisi değildir**. Nav2 ve EKF onu kullanmaz;
> yalnızca `motion_probe` gibi kabul testlerinde gerçek gövde hareketini
> ölçmek için vardır.

### Mecanum temas modeli (kritik)

Yanal (strafe) hareket, teker temasının **anizotropik sürtünmesiyle** üretilir:
`mu=1.0` makara ekseni boyunca, `mu2=0.0` ona dik yönde. Yön `fdir1` ile verilir
ve **gövdeye sabitlenmiş gerçek bir SDF link'ine** bağlanmalıdır:

```xml
<fdir1 gz:expressed_in="base_footprint">1 -1 0</fdir1>
```

Çaprazlar Harmonic'in resmî referans dünyasıyla aynıdır
(`gz-sim8/worlds/mecanum_drive.sdf`): FL/RR = `1 -1 0`, FR/RL = `1 1 0`.

Frame **`base_link` olamaz**: `urdf`→`sdf` dönüşümü sabit eklemli `base_link`'i
`base_footprint` içine lump eder ve geriye yalnızca bir SDF `frame` elemanı
kalır; dartsim ise gerçek bir link (body node) ister. Ayrıntı ve belirtiler:
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Gerçek araç ayrımı

Gerçekte `ros2_control_node` ayrı bir proses olarak çalışır ve URDF'yi yine
`/robot_description` topic'inden alır. Hardware plugin'i
`MecanumSystemInterface`'tir; `wheel/commands` ve `wheel/states` üzerinden
firmware ile konuşur ([LOW_LEVEL_INTERFACE.md](LOW_LEVEL_INTERFACE.md)).

micro-ROS agent ve LiDAR sürücüsü **bilerek ayrı proseslerdir**: cihaz
kimlikleri ve sürücü modeli araca göre değişir, çekirdek navigasyon koduna
gömülmez.

# Sorun giderme

Controller manager URDF bekliyorsa `/robot_description` yayınını kontrol edin. Controller configure olamıyorsa spawner'ın doğru YAML'ı `--param-file` ile aldığını inceleyin.

Komut zincirini `cmd_vel_teleop`/`cmd_vel_nav`, `cmd_vel_selected`, `cmd_vel_smoothed`, `cmd_vel`, `mecanum_drive_controller/reference` sırasıyla inceleyin. Zincirin tamamı `TwistStamped` olmalıdır; aynı topic üzerinde `Twist` görülmesi yapılandırma hatasıdır.

Gazebo plugin yüklenmiyorsa `GZ_SIM_SYSTEM_PLUGIN_PATH` ve `libgz_ros2_control-system.so` varlığını kontrol edin. Nav2 için `map → odom → base_footprint`, `/scan`, `odometry/filtered` ve lifecycle durumlarını kontrol edin. AMCL ile SLAM Toolbox'ı aynı anda çalıştırmayın.

## Yanal (strafe) hareket çalışmıyor veya yön değiştiriyor

**Belirti:** Teker hızları doğru ve sabit, ama gövde yanal hızı işaret
değiştirerek salınıyor; aynı komut ardışık koşularda zıt sonuç veriyor
(ölçüldü: +0.16 m ve -0.21 m). Salınım periyodu teker dönüş periyoduna
eşit (0.9231 rad/s → 6.81 s; ölçülen tepe 3.58 s ≈ yarım periyot).

**Bu bir teker sırası / fdir çaprazı hatası DEĞİLDİR.** Çaprazları
denemeyin; her iki çapraz da aynı bozuk sonucu verir.

**Kök neden:** `fdir1` sürtünme yönünün bağlandığı frame çözülemiyor.
`urdf`→`sdf` dönüşümü sabit eklemli `base_link`'i `base_footprint`
içine lump eder; geriye yalnızca bir SDF `frame` elemanı kalır. dartsim
ise `setFirstFrictionDirectionFrame` için **gerçek bir link (body node)**
ister. Çözülemeyen frame **sessizce** yok sayılır ve sürtünme yönü
tekerle birlikte döner.

**Çözüm:** `gz:expressed_in` değerini gerçek bir link'e bağlayın:

```xml
<fdir1 gz:expressed_in="base_footprint">1 -1 0</fdir1>
```

**Doğrulama:** Üretilen SDF'te frame'in `<link>` olarak var olduğunu
görün (`<frame>` YETMEZ):

```bash
xacro mecanum_robot.xacro > /tmp/d.urdf && gz sdf -p /tmp/d.urdf > /tmp/d.sdf
grep -o "<fdir1[^<]*</fdir1>" /tmp/d.sdf
grep -o "<link name='base_footprint'" /tmp/d.sdf   # cikti VERMELI
```

Çaprazlar Harmonic'in resmî referans dünyasıyla aynıdır
(`/opt/ros/jazzy/opt/gz_sim_vendor/share/gz/gz-sim8/worlds/mecanum_drive.sdf`):
FL/RR = `1 -1 0`, FR/RL = `1 1 0`.

## slam_toolbox çalışıyor ama /map ve map→odom yok

**Belirti:** `ros2 node list` slam_toolbox'ı gösterir, ama `/map`
yayınlanmaz ve `tf2_echo map odom` "frame does not exist" der.

**Kök neden:** Jazzy'de `async_slam_toolbox_node` bir **lifecycle**
düğümüdür. Düz `Node` olarak başlatılırsa `unconfigured` durumunda
kalır ve hiçbir şey yayınlamaz.

**Kontrol:**

```bash
ros2 lifecycle get /slam_toolbox    # unconfigured [1] ise sorun budur
```

**Çözüm:** `LifecycleNode` kullanın ve configure/activate geçişlerini
açıkça tetikleyin (`mecanum_navigation/launch/mapping.launch.py`
bunu yapar). Desen resmî örnekten alınmıştır:
`/opt/ros/jazzy/share/slam_toolbox/launch/online_async_launch.py`.
`OnStateTransition` **`launch_ros.event_handlers`** içindedir
(`launch.event_handlers` DEĞİL); `matches_action` ise `launch.events`
içindedir.

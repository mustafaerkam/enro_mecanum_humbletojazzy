# Humble baseline

Başlangıç sistemi Ubuntu 22.04, ROS 2 Humble ve Gazebo Fortress'tir. Paketler robot modeli, control, simulation, navigation, teleop, bringup ve doğrulama araçları olarak ayrılmıştır.

Komut akışı `cmd_vel_teleop` veya `cmd_vel_nav` → `twist_mux` → Velocity Smoother → Collision Monitor → mecanum controller şeklindedir. Humble hattı `Twist` kullanıyordu; Jazzy portunda tüm zincir `TwistStamped` taşır.

Teker sırası `[FL, FR, RL, RR]`; komut ve hız `rad/s`, feedback konumu kümülatif `rad` değeridir. Controller `wheel/odometry`, EKF `odometry/filtered` ve tek `odom → base_footprint` TF'sini üretir. AMCL veya SLAM Toolbox tek başına `map → odom` sahibidir. Robot State Publisher kalan TF'leri üretir.

URDF geometrisi: yarıçap 0.1625 m, wheelbase 0.80 m, separation 1.08 m ve `lx + ly = 0.94 m`. Motor/encoder işaretleri firmware olmadığı için doğrulanmamıştır.

10 Eylül 2026 baseline build'in ilk denemesi sandbox ccache dizini yüzünden durdu. `CCACHE_TEMPDIR=/tmp/enro-ccache-tmp` ile tekrarlandığında yedi paketin tamamı derlendi; 16 testte hata yoktu ve 2 test skip edildi.

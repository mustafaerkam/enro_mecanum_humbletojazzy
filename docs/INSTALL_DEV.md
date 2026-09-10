# Geliştirme kurulumu

İki geliştirme yolu vardır. Her ikisi de **aynı** simülasyon akışını çalıştırır.

---

## Ubuntu 24.04 — native Jazzy

```bash
source /opt/ros/jazzy/setup.bash
sudo apt update
sudo apt install -y python3-colcon-common-extensions python3-rosdep
sudo rosdep init 2>/dev/null || true
rosdep update --rosdistro jazzy

./scripts/build_jazzy.sh
source install_jazzy/setup.bash
```

---

## Ubuntu 22.04 — Jazzy Docker

Host'ta **Humble kalır**; Jazzy/Harmonic yalnızca konteynerde çalışır.

### Docker kurulumu (bir kez)

```bash
./scripts/install_docker_host.sh
```

Betik kullanıcıyı `docker` grubuna ekler. **Grup üyeliği mevcut oturumda etkin
olmaz** — yeni bir terminal açın veya `newgrp docker` çalıştırın. Doğrulama:

```bash
docker run --rm hello-world
```

> Grup üyeliğini yenileyemediğiniz bir oturumdaysanız komutları
> `sg docker -c "..."` ile sarmalayabilirsiniz.

### İmaj ve derleme

```bash
cp .env.example .env
docker compose build jazzy
docker compose run --rm jazzy ./scripts/build_jazzy.sh
docker compose run --rm jazzy ./scripts/test_jazzy.sh
```

`.env` içindeki `USER_ID`/`GROUP_ID` değerlerini kendi kullanıcınızla
eşleştirin (`id -u`, `id -g`); aksi halde derleme çıktıları host'ta root'a ait
olur.

### Build çıktılarının ayrılması

Humble ve Jazzy çıktıları **asla karışmaz**:

| Dağıtım | build | install | log |
|---|---|---|---|
| Humble (host) | `build_humble/` | `install_humble/` | `log_humble/` |
| Jazzy (Docker/native) | `build_jazzy/` | `install_jazzy/` | `log_jazzy/` |

Kaynak kod konteynere `/workspace` olarak bağlanır; çıktılar host'taki repo
dizinine düşer.

### GUI (Gazebo + RViz ekranda)

`.env` içindeki `DISPLAY` **kendi ekranınızla eşleşmelidir**:

```bash
echo $DISPLAY          # ornegin :1
```

> `.env.example` varsayılanı `:0`'dır. Ekranınız `:1` ise `.env` dosyasında
> düzeltmezseniz pencere açılmaz — compose sessizce `:0`'a düşer.

X11 erişimi verin, simülasyonu başlatın, sonra erişimi geri kısıtlayın:

```bash
xhost +local:
docker compose run --rm jazzy ros2 launch mecanum_bringup sim_nav.launch.py
xhost -local:
```

`xhost +local:` her yeniden başlatmada tekrar gerekir.

### Aynı simülasyona ikinci terminal bağlamak

Teleop veya harita kaydetme için simülasyonu **adlandırılmış** konteynerde
başlatın:

```bash
docker compose run -d --name enro-sim jazzy \
  ros2 launch mecanum_bringup sim_mapping.launch.py headless:=true rviz:=false
```

Aynı konteynere bağlanın:

```bash
docker exec -it enro-sim bash -lc \
  'source /opt/ros/jazzy/setup.bash && source /workspace/install_jazzy/setup.bash && \
   ros2 topic list'
```

Bitince kaldırın: `docker rm -f enro-sim`

### DDS ayarları

Varsayılan olarak tüm ROS süreçleri **aynı konteynerde** çalışır ve
`ROS_LOCALHOST_ONLY=1` kullanılır.

Host ile konteyner arasında gerçekten DDS haberleşmesi gerekiyorsa şunlar
**birlikte** ayarlanmalıdır: host network, aynı `ROS_DOMAIN_ID` (42),
`RMW_IMPLEMENTATION=rmw_fastrtps_cpp`, `ROS_LOCALHOST_ONLY=0`.

> Karışık Humble-host / Jazzy-konteyner ROS graph'ı **üretim mimarisi
> değildir**; yalnızca geçici hata ayıklama içindir. İki farklı ROS dağıtımı
> aynı graph'ta desteklenmez.

---

## Testler

```bash
./scripts/test_jazzy.sh            # birim testler + statik sozlesme denetimi
./scripts/smoke_jazzy.sh nav       # gercek headless sim: Nav2 profili
./scripts/smoke_jazzy.sh mapping   # gercek headless sim: SLAM + harita kaydetme
```

Smoke testleri gerçek bir simülasyon açtığı için statik testlerin
yakalayamadığı çalışma zamanı hatalarını yakalar. GPU'suz ortamda (CI)
yazılım rasterizer gerekir:

```bash
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
```

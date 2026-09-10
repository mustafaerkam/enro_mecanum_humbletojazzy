#!/usr/bin/env bash
# Headless runtime smoke test (CI + yerel).
#
# Statik testler (contract_audit, check_urdf) iki gercek port hatasini
# YAKALAYAMADI; ikisi de yalnizca calisma zamaninda gorunur:
#   1) fdir1 friction frame cozulemiyordu -> yanal hareket salindi
#   2) slam_toolbox lifecycle -> /map ve map->odom hic olusmadi
# Bu yuzden CI'da gercek bir simulasyon acilir ve sozlesmeler kontrol edilir.
#
# Kullanim:
#   ./scripts/smoke_jazzy.sh            # sim_nav profili (varsayilan)
#   ./scripts/smoke_jazzy.sh mapping    # sim_mapping profili (SLAM)
set -eo pipefail

PROFILE="${1:-nav}"
TIMEOUT_READY="${SMOKE_TIMEOUT:-180}"
LOG_DIR="${SMOKE_LOG_DIR:-/tmp/mecanum_smoke}"
mkdir -p "$LOG_DIR"

source /opt/ros/jazzy/setup.bash
source install_jazzy/setup.bash
set -u

export ROS_LOCALHOST_ONLY=1
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
ros2 daemon stop >/dev/null 2>&1 || true

case "$PROFILE" in
  nav)     LAUNCH="sim_nav.launch.py" ;;
  mapping) LAUNCH="sim_mapping.launch.py" ;;
  *) echo "HATA: bilinmeyen profil '$PROFILE' (nav|mapping)"; exit 2 ;;
esac

FAILED=0
pass() { echo "PASS  $1"; }
fail() {
  echo "FAIL  $1"
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    printf '::error title=Smoke %s::%s\n' "$PROFILE" "$1"
  fi
  FAILED=1
}

# Lifecycle dugumleri sirayla aktiflesir; TEK bir ornekleme yaris kosulu
# yaratir (olculdu: ayni komut bir kosuda 26/26 PASS, sonraki kosuda
# collision_monitor 'inactive' yakalandi). Bu yuzden bir sure BEKLERIZ.
LAST_STATE=""
wait_active() {
  local node="$1" i
  for i in $(seq 1 "${LIFECYCLE_WAIT:-45}"); do
    LAST_STATE="$(timeout 10 ros2 lifecycle get "/$node" 2>/dev/null | head -1 || true)"
    case "$LAST_STATE" in active*) return 0 ;; esac
    sleep 1
  done
  return 1
}

cleanup() {
  [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null || true
  [ -n "${LAUNCH_PID:-}" ] && kill -INT -- "-$LAUNCH_PID" 2>/dev/null || true
  if [ -n "${LAUNCH_PID:-}" ]; then
    for _ in $(seq 1 15); do
      kill -0 "$LAUNCH_PID" 2>/dev/null || break
      sleep 1
    done
    kill -TERM -- "-$LAUNCH_PID" 2>/dev/null || true
    wait "$LAUNCH_PID" 2>/dev/null || true
  fi
  pkill -9 -f "gz sim" 2>/dev/null || true
  ros2 daemon stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== $LAUNCH (headless) baslatiliyor =="
setsid ros2 launch mecanum_bringup "$LAUNCH" headless:=true rviz:=false \
  > "$LOG_DIR/launch.log" 2>&1 &
LAUNCH_PID=$!
sleep 5

# --- controller'lar active olana kadar bekle ---
ready=0
for _ in $(seq 1 "$TIMEOUT_READY"); do
  if ros2 control list_controllers 2>/dev/null \
       | grep -q "mecanum_drive_controller.*active"; then
    ready=1; break
  fi
  kill -0 "$LAUNCH_PID" 2>/dev/null || { echo "HATA: launch erken oldu"; tail -30 "$LOG_DIR/launch.log"; exit 1; }
  sleep 1
done
[ "$ready" = 1 ] && pass "controller_manager + mecanum_drive_controller active" \
                || { fail "controller'lar $TIMEOUT_READY s icinde active olmadi"; tail -30 "$LOG_DIR/launch.log"; exit 1; }

ros2 control list_controllers 2>/dev/null | grep -q "joint_state_broadcaster.*active" \
  && pass "joint_state_broadcaster active" || fail "joint_state_broadcaster active degil"

sleep 8

# Nav ve mapping profilleri ayni son guvenlik zincirini kullanir. Mapping
# profili Nav2 sunucularini baslatmadigi icin bu iki lifecycle dugumunun
# aktivasyonu, topic denetiminden sonra kalabilecek kadar uzun surebilir.
# Once gercekten active olmalarini beklemek graph baslangic yarisini onler.
for n in velocity_smoother collision_monitor; do
  if wait_active "$n"; then
    pass "$n active"
  else
    fail "$n active degil: ${LAST_STATE:-yanit yok}"
  fi
done

wait_topic() {
  local topic="$1"
  for _ in $(seq 1 30); do
    ros2 topic list 2>/dev/null | grep -qx "$topic" && return 0
    sleep 1
  done
  return 1
}

# --- zorunlu topic'ler ---
for t in /scan /imu/data_raw /joint_states /wheel/odometry /odometry/filtered /tf /tf_static /cmd_vel; do
  wait_topic "$t" && pass "topic $t" || fail "topic $t yok"
done

# Mapping'de klavye dugumu bilerek launch icinde baslatilmaz. Sifir hizli
# gecici bir teleop yayincisi, giris aboneligini ve devamindaki smoother /
# collision cikislarini hareket ettirmeden uctan uca gorunur hale getirir.
ros2 topic pub -r 10 /cmd_vel_teleop geometry_msgs/msg/TwistStamped \
  "{header: {frame_id: base_footprint}, twist: {}}" \
  >"$LOG_DIR/cmd_vel_probe.log" 2>&1 &
PROBE_PID=$!
sleep 2

# --- komut zinciri UCTAN UCA TwistStamped olmali ---
# Jazzy twist_mux TwistStamped dinler; zincirde tek bir Twist kalirsa
# komut controller'a HIC ulasmaz (bu hata bir kez yasandi).
for t in /cmd_vel_nav /cmd_vel_teleop /cmd_vel_selected /cmd_vel_smoothed /cmd_vel; do
  wait_topic "$t" || true
  ty="$(ros2 topic type "$t" 2>/dev/null || true)"
  if [ "$ty" = "geometry_msgs/msg/TwistStamped" ]; then
    pass "$t TwistStamped"
  elif [ -z "$ty" ]; then
    fail "$t yok"
  else
    fail "$t tipi TwistStamped degil: $ty"
  fi
done

probe_info="$(ros2 topic info /cmd_vel_teleop 2>/dev/null || true)"
case "$probe_info" in
  *"Subscription count: 0"*|"") fail "/cmd_vel_teleop twist_mux aboneligi yok" ;;
  *) pass "/cmd_vel_teleop twist_mux aboneligi" ;;
esac
kill "$PROBE_PID" 2>/dev/null || true
wait "$PROBE_PID" 2>/dev/null || true
unset PROBE_PID

# --- TF: odom -> base_footprint ---
# use_sim_time ZORUNLU: sim saatinde calisirken tf2_echo'yu wall clock ile
# baslatirsak once "frame does not exist" yazar ve kisa timeout'ta TF varken
# bile bos donebilir (bir kez yanlis FAIL uretti).
# NOT: 'grep -q' pipe'i erken kapatir; yayin yapan bir surecle birlestiginde
# SIGPIPE (rc=141) olusur ve 'set -o pipefail' bunu HATA sayar (bu da bir kez
# yanlis FAIL uretti). Bu yuzden ciktiyi degiskene alip ayrica arariz.
tf_ok() {
  local out
  out="$(timeout 20 ros2 run tf2_ros tf2_echo "$1" "$2" \
           --ros-args -p use_sim_time:=true 2>/dev/null || true)"
  case "$out" in *Translation*) return 0 ;; *) return 1 ;; esac
}
tf_ok odom base_footprint \
  && pass "TF odom -> base_footprint" || fail "TF odom -> base_footprint yok"

if [ "$PROFILE" = "mapping" ]; then
  # --- SLAM: lifecycle + /map + map->odom ---
  # Jazzy'de async_slam_toolbox_node LIFECYCLE dugumudur; duz Node olarak
  # baslatilirsa 'unconfigured' kalir ve hicbir sey yayinlamaz.
  if wait_active slam_toolbox; then
    pass "slam_toolbox lifecycle active"
  else
    fail "slam_toolbox lifecycle 'active' degil: ${LAST_STATE:-yanit yok}"
  fi

  map_out="$(timeout 40 ros2 topic echo /map --once --field info 2>/dev/null || true)"
  case "$map_out" in
    *resolution*) pass "/map yayinlaniyor" ;;
    *)            fail "/map yayinlanmiyor" ;;
  esac

  tf_ok map odom && pass "TF map -> odom" || fail "TF map -> odom yok"

  # map->odom TEK sahip olmali (SLAM ve AMCL ayni anda yayinlayamaz)
  ros2 node list 2>/dev/null | grep -qE "^/amcl$" \
    && fail "mapping oturumunda AMCL calisiyor (map->odom cift sahip)" \
    || pass "mapping oturumunda AMCL yok"

  # --- harita kaydetme akisi ---
  # NOT: map_saver_cli'ye use_sim_time VERILMEZ; sim saatiyle calistirilirsa
  # "Failed to spin map subscription" ile duser (olculdu).
  # save_map_timeout: varsayilan deger bu ortamda YETMIYOR; map_saver
  # "Failed to spin map subscription" ile duser (olculdu: varsayilanla
  # basarisiz, 20 s ile basarili). use_sim_time VERILMEZ - sim saatiyle
  # calistirilirsa ayni hatayla duser.
  save_out="$(timeout 60 ros2 run nav2_map_server map_saver_cli \
                -f "$LOG_DIR/smoke_map" \
                --ros-args -p save_map_timeout:=20.0 2>&1 || true)"
  if [ -f "$LOG_DIR/smoke_map.pgm" ] && [ -f "$LOG_DIR/smoke_map.yaml" ]; then
    pass "harita kaydetme (.pgm + .yaml)"
  else
    fail "harita kaydedilemedi"
    echo "$save_out" | tail -5
  fi
else
  # --- Nav2 lifecycle dugumleri ---
  for n in controller_server planner_server bt_navigator behavior_server \
           amcl map_server; do
    if wait_active "$n"; then
      pass "$n active"
    else
      fail "$n active degil: ${LAST_STATE:-yanit yok}"
    fi
  done

  ros2 action list 2>/dev/null | grep -qx /navigate_to_pose \
    && pass "action /navigate_to_pose" || fail "action /navigate_to_pose yok"

  if timeout 180 ros2 run mecanum_testing runtime_acceptance \
       >"$LOG_DIR/runtime_acceptance.log" 2>&1; then
    pass "ileri/geri/yanal/dönüş + NavigateToPose SUCCEEDED"
  else
    fail "hareket veya Nav2 hedef kabul testi"
    cat "$LOG_DIR/runtime_acceptance.log"
    if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
      runtime_summary="$(tail -20 "$LOG_DIR/runtime_acceptance.log" \
        | tr '\n' ';' | sed 's/%/%25/g; s/\r/%0D/g; s/;/%0A/g')"
      printf '::error title=Runtime acceptance details::%s\n' "$runtime_summary"
    fi
  fi

  # SLAM ve AMCL ayni anda map->odom yayinlamamali
  ros2 node list 2>/dev/null | grep -qE "^/slam_toolbox$" \
    && fail "nav oturumunda slam_toolbox calisiyor (map->odom cift sahip)" \
    || pass "nav oturumunda slam_toolbox yok"
fi

echo
[ "$FAILED" = 0 ] && echo "SMOKE ($PROFILE): TUM KONTROLLER PASS" \
                  || { echo "SMOKE ($PROFILE): BASARISIZ"; tail -40 "$LOG_DIR/launch.log"; }
exit "$FAILED"

#!/usr/bin/env bash
# Gerçek araç launch ağacının donanımsız interface/lifecycle smoke testi.
# Fiziksel hareket kanıtı değildir; transport:=mock kullanır.
set -eo pipefail

PROFILE="${1:-nav}"
TIMEOUT_READY="${SMOKE_TIMEOUT:-120}"
LOG_DIR="${SMOKE_LOG_DIR:-/tmp/mecanum_smoke_real_${PROFILE}}"
mkdir -p "$LOG_DIR"

source /opt/ros/jazzy/setup.bash
source install_jazzy/setup.bash
set -u
export ROS_LOCALHOST_ONLY=1
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
ros2 daemon stop >/dev/null 2>&1 || true

case "$PROFILE" in
  nav) LAUNCH=real_nav.launch.py ;;
  mapping) LAUNCH=real_mapping.launch.py ;;
  *) echo "HATA: bilinmeyen profil '$PROFILE' (nav|mapping)"; exit 2 ;;
esac

cleanup() {
  [ -n "${LAUNCH_PID:-}" ] && kill -INT -- "-$LAUNCH_PID" 2>/dev/null || true
  if [ -n "${LAUNCH_PID:-}" ]; then
    for _ in $(seq 1 15); do
      kill -0 "$LAUNCH_PID" 2>/dev/null || break
      sleep 1
    done
    kill -TERM -- "-$LAUNCH_PID" 2>/dev/null || true
    wait "$LAUNCH_PID" 2>/dev/null || true
  fi
  ros2 daemon stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

FAILED=0
pass() { echo "PASS  $1"; }
fail() {
  echo "FAIL  $1"
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    printf '::error title=Real mock %s::%s\n' "$PROFILE" "$1"
  fi
  FAILED=1
}

launch_alive() { kill -0 "$LAUNCH_PID" 2>/dev/null; }

wait_controller_active() {
  local controller="$1" controllers
  for _ in $(seq 1 "$TIMEOUT_READY"); do
    controllers="$(timeout 10 ros2 control list_controllers 2>/dev/null || true)"
    if grep -q "${controller}.*active" <<<"$controllers"; then
      return 0
    fi
    launch_alive || return 1
    sleep 1
  done
  return 1
}

wait_topic_message() {
  local topic="$1"
  # --no-daemon eski smoke oturumundan kalabilecek graph onbellegini devre
  # disi birakir. best_available, publisher'in gercek QoS profilini secer;
  # robot_description icin transient_local veriyi de boyle alabiliriz.
  for _ in $(seq 1 6); do
    if ros2 topic echo "$topic" --once --no-daemon --spin-time 2 \
         --qos-profile best_available --timeout 8 >/dev/null 2>&1; then
      return 0
    fi
    launch_alive || return 1
  done
  return 1
}

wait_node() {
  local node="$1"
  local nodes
  for _ in $(seq 1 "${NODE_WAIT:-60}"); do
    nodes="$(timeout 10 ros2 node list --no-daemon --spin-time 2 \
      2>/dev/null || true)"
    if grep -Fxq "/$node" <<<"$nodes"; then
      return 0
    fi
    launch_alive || return 1
    sleep 1
  done
  return 1
}

setsid ros2 launch mecanum_bringup "$LAUNCH" transport:=mock feedback_mode:=required \
  >"$LOG_DIR/launch.log" 2>&1 &
LAUNCH_PID=$!
sleep 3

if wait_controller_active mecanum_drive_controller; then
  pass 'mecanum_drive_controller active'
else
  fail "mecanum_drive_controller ${TIMEOUT_READY} s icinde active olmadi"
  tail -60 "$LOG_DIR/launch.log"
  exit 1
fi

for controller in joint_state_broadcaster; do
  wait_controller_active "$controller" \
    && pass "$controller active" \
    || fail "$controller active degil"
done

for topic in /joint_states /wheel/odometry /robot_description; do
  wait_topic_message "$topic" \
    && pass "$topic yayinlaniyor" \
    || fail "$topic bekleme suresinde yayinlanmadi"
done

# Bu profil fiziksel LiDAR/IMU ve RViz'den verilen ilk pozu kasitli olarak
# icermez. Dolayisiyla planner gibi Nav2 dugumleri 'inactive' kalabilir; bu
# donanimsiz testte dogru sozlesme, surecin graph'ta hazir olmasidir. Tam
# lifecycle aktivasyonu sim smoke ve gercek arac kabul testinde dogrulanir.
if [ "$PROFILE" = nav ]; then
  for node in map_server amcl controller_server planner_server bt_navigator \
              behavior_server velocity_smoother collision_monitor; do
    if wait_node "$node"; then
      pass "$node calisiyor"
    else
      fail "$node ${NODE_WAIT:-60} s icinde graph'ta gorunmedi"
    fi
  done
else
  for node in slam_toolbox velocity_smoother collision_monitor; do
    if wait_node "$node"; then
      pass "$node calisiyor"
    else
      fail "$node ${NODE_WAIT:-60} s icinde graph'ta gorunmedi"
    fi
  done
fi

echo "REAL MOCK ($PROFILE): $([ "$FAILED" = 0 ] && echo PASS || echo FAIL)"
[ "$FAILED" = 0 ] || tail -60 "$LOG_DIR/launch.log"
exit "$FAILED"

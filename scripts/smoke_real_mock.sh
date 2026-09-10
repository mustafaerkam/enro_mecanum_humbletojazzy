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

setsid ros2 launch mecanum_bringup "$LAUNCH" transport:=mock feedback_mode:=required \
  >"$LOG_DIR/launch.log" 2>&1 &
LAUNCH_PID=$!
sleep 8

for _ in $(seq 1 "$TIMEOUT_READY"); do
  if ros2 control list_controllers 2>/dev/null | grep -q 'mecanum_drive_controller.*active'; then
    break
  fi
  kill -0 "$LAUNCH_PID" 2>/dev/null || { tail -50 "$LOG_DIR/launch.log"; exit 1; }
  sleep 1
done

FAILED=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILED=1; fi; }
check 'mecanum_drive_controller active' "ros2 control list_controllers 2>/dev/null | grep -q 'mecanum_drive_controller.*active'"
check 'joint_state_broadcaster active' "ros2 control list_controllers 2>/dev/null | grep -q 'joint_state_broadcaster.*active'"
check '/joint_states yayınlanıyor' "timeout 15 ros2 topic echo /joint_states --once >/dev/null 2>&1"
check '/wheel/odometry yayınlanıyor' "timeout 15 ros2 topic echo /wheel/odometry --once >/dev/null 2>&1"
check '/robot_description yayınlanıyor' "timeout 15 ros2 topic echo /robot_description --once >/dev/null 2>&1"

if [ "$PROFILE" = nav ]; then
  for node in map_server amcl controller_server planner_server bt_navigator; do
    check "$node çalışıyor" "ros2 node list 2>/dev/null | grep -qx '/$node'"
  done
else
  check 'slam_toolbox çalışıyor' "ros2 node list 2>/dev/null | grep -qx '/slam_toolbox'"
fi

echo "REAL MOCK ($PROFILE): $([ "$FAILED" = 0 ] && echo PASS || echo FAIL)"
exit "$FAILED"

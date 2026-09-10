#!/usr/bin/env bash
set -eo pipefail

source /opt/ros/jazzy/setup.bash
source install_jazzy/setup.bash
set -u
colcon --log-base log_jazzy_test test \
  --build-base build_jazzy \
  --install-base install_jazzy
colcon test-result --test-result-base build_jazzy --verbose
python3 -m compileall -q src
python3 src/mecanum_testing/mecanum_testing/contract_audit.py --workspace .
xacro src/mecanum_robot_description/urdf/sim_robot.xacro > /tmp/mecanum_jazzy.urdf
check_urdf /tmp/mecanum_jazzy.urdf

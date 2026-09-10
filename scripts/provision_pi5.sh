#!/usr/bin/env bash
set -eo pipefail

if [ "$(dpkg --print-architecture)" != "arm64" ]; then
  echo "ERROR: Raspberry Pi 5 arm64 bekleniyor; bulunan: $(dpkg --print-architecture)" >&2
  exit 1
fi
source /etc/os-release
if [ "${VERSION_ID}" != "24.04" ]; then
  echo "ERROR: Ubuntu 24.04 bekleniyor; bulunan: ${PRETTY_NAME}" >&2
  exit 1
fi
if [ ! -f /opt/ros/jazzy/setup.bash ]; then
  echo "ERROR: /opt/ros/jazzy bulunamadi. Once ROS 2 Jazzy kurun." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y \
  python3-colcon-common-extensions python3-rosdep \
  ros-jazzy-micro-ros-agent ros-jazzy-navigation2 ros-jazzy-nav2-bringup \
  ros-jazzy-rplidar-ros \
  ros-jazzy-robot-localization ros-jazzy-ros2-control \
  ros-jazzy-ros2-controllers ros-jazzy-slam-toolbox ros-jazzy-twist-mux \
  ros-jazzy-xacro

source /opt/ros/jazzy/setup.bash
set -u
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
  sudo rosdep init
fi
rosdep update --rosdistro jazzy
rosdep install --from-paths src --ignore-src -r -y --rosdistro jazzy \
  --skip-keys="gz_ros2_control ros_gz_bridge ros_gz_sim"
colcon --log-base log_jazzy build \
  --symlink-install --build-base build_jazzy --install-base install_jazzy \
  --cmake-args -DCMAKE_BUILD_TYPE=Release

echo "Pi 5 high-level kurulum tamamlandi. Sonraki adimlar: docs/INSTALL_PI5.md"

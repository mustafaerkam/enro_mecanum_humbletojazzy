#!/usr/bin/env bash
set -eo pipefail

source /opt/ros/jazzy/setup.bash
set -u
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
  sudo rosdep init
fi
if [ ! -f "${HOME}/.ros/rosdep/sources.cache/index" ]; then
  rosdep update --rosdistro jazzy
fi
sudo apt-get update
rosdep install --from-paths src --ignore-src -r -y --rosdistro jazzy
colcon --log-base log_jazzy build \
  --symlink-install \
  --build-base build_jazzy \
  --install-base install_jazzy \
  --cmake-args -DCMAKE_BUILD_TYPE=Release

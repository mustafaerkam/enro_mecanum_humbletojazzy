#!/usr/bin/env bash
set -e
source /opt/ros/jazzy/setup.bash
if [ -f /workspace/install_jazzy/setup.bash ]; then
  source /workspace/install_jazzy/setup.bash
fi
exec "$@"

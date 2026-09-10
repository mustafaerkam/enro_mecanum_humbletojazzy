#!/usr/bin/env bash
set -euo pipefail

source /etc/os-release
if [ "${VERSION_ID}" != "22.04" ]; then
  echo "ERROR: Bu kurulum Ubuntu 22.04 host icindir; bulunan: ${PRETTY_NAME}" >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$(id -un)"

echo "Docker kuruldu. Grup uyeliginin uygulanmasi icin oturumu kapatip acin."
echo "Ardindan: cd ~/enro_mecanum_humbletojazzy && docker compose build jazzy"

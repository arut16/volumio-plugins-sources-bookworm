#!/usr/bin/env bash
set -euo pipefail

APP_NAME="volumio-screensaver"
APP_DIR="/opt/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
ENV_FILE="/etc/${APP_NAME}.env"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

systemctl stop "${APP_NAME}.service" || true
systemctl disable "${APP_NAME}.service" || true
rm -f "${SERVICE_FILE}"
systemctl daemon-reload
rm -rf "${APP_DIR}"
rm -f "${ENV_FILE}"

echo "Uninstallation completed."
echo "pluginuninstallend"

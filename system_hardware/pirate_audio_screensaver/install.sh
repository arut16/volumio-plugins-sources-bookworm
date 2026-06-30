#!/bin/sh
set -eu

APP_NAME="volumio-screensaver"
APP_DIR="/opt/${APP_NAME}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
ENV_FILE="/etc/${APP_NAME}.env"
REPO_URL="${REPO_URL:-https://github.com/arut16/Ecran-Veille-Volumio.git}"
FAST_INSTALL="${FAST_INSTALL:-1}"

runtime_already_installed() {
  [ -x "${APP_DIR}/venv/bin/volumio-screensaver" ] && [ -f "${SERVICE_FILE}" ]
}

cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "${TMP_DIR}" ]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT INT TERM

if [ "$(id -u)" -ne 0 ]; then
  if runtime_already_installed; then
    echo "Runtime already installed. Skipping privileged setup for local Volumio plugin registration."
    echo "plugininstallend"
    exit 0
  fi

  if sudo -n true 2>/dev/null; then
    exec sudo -E sh "$0" "$@"
  fi

  echo "This plugin needs privileged setup, but sudo is not available non-interactively."
  echo "Run once manually from this directory: sudo sh install.sh"
  echo "Then run again: volumio plugin install"
  exit 1
fi

apt_packages="git python3 python3-dev python3-pip python3-venv python3-pil python3-numpy python3-spidev libgpiod2 fonts-dejavu-core build-essential python3-rpi.gpio"
missing_packages=""
for package in ${apt_packages}; do
  if ! dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "install ok installed"; then
    missing_packages="${missing_packages} ${package}"
  fi
done

RPI_GPIO_FROM_PIP=0
if [ -n "${missing_packages}" ]; then
  apt-get update
  if ! apt-get install -y ${missing_packages}; then
    missing_without_gpio=""
    for package in ${missing_packages}; do
      if [ "${package}" != "python3-rpi.gpio" ]; then
        missing_without_gpio="${missing_without_gpio} ${package}"
      fi
    done
    if [ -n "${missing_without_gpio}" ]; then
      apt-get install -y ${missing_without_gpio}
    fi
    RPI_GPIO_FROM_PIP=1
  fi
else
  echo "System dependencies already installed, apt skipped."
fi

TMP_DIR="$(mktemp -d)"
git clone --depth=1 "${REPO_URL}" "${TMP_DIR}"

mkdir -p "${APP_DIR}"
python3 -m venv --system-site-packages "${APP_DIR}/venv"

if [ "${FAST_INSTALL}" != "1" ] || ! "${APP_DIR}/venv/bin/python" - <<'PY'
import importlib.util
import sys
required = ["st7789", "gpiodevice", "numpy", "spidev", "gpiod"]
missing = [name for name in required if importlib.util.find_spec(name) is None]
sys.exit(1 if missing else 0)
PY
then
  "${APP_DIR}/venv/bin/python" -m pip install --upgrade pip setuptools wheel
  "${APP_DIR}/venv/bin/python" -m pip install --no-cache-dir --force-reinstall "${TMP_DIR}"
else
  echo "Python dependencies already installed, reinstalling package only."
  "${APP_DIR}/venv/bin/python" -m pip install --no-cache-dir --force-reinstall --no-build-isolation --no-deps "${TMP_DIR}"
fi

if [ "${RPI_GPIO_FROM_PIP}" -eq 1 ]; then
  "${APP_DIR}/venv/bin/python" -m pip install RPi.GPIO
fi

install -m 0644 "${TMP_DIR}/systemd/${APP_NAME}.service" "${SERVICE_FILE}"

if [ ! -f "${ENV_FILE}" ]; then
  install -m 0644 "${TMP_DIR}/config/${APP_NAME}.env.example" "${ENV_FILE}"
fi

systemctl daemon-reload

echo "Installation completed. The service will be started when the plugin is enabled."
echo "plugininstallend"

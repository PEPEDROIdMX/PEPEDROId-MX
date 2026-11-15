#!/usr/bin/env bash
set -Eeuo pipefail

REPO="PEPEDROIdMX/PEPEDROID-MX"
ARCHIVE="PEPEDROID-GITHUB-PACKAGE-v0.7.zip"
DOMAIN="pepedroidmxxx.store"
SERVER_IP="78.13.10.162"
WORKDIR="/root/pepedroid-bootstrap"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta como root: sudo bash install.sh"
  exit 1
fi
if [[ "$(. /etc/os-release && echo "${ID}")" != "ubuntu" ]]; then
  echo "Este instalador requiere Ubuntu."
  exit 1
fi

echo "=== PEPEDROID: instalacion automatizada ==="
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip ca-certificates gnupg openssl

echo "[1/5] Descargando paquete desde GitHub..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
curl -fL "https://raw.githubusercontent.com/${REPO}/main/${ARCHIVE}" -o "${WORKDIR}/${ARCHIVE}"
unzip -q "${WORKDIR}/${ARCHIVE}" -d "$WORKDIR"

APP_SOURCE="${WORKDIR}/pepedroid"
if [[ ! -x "${APP_SOURCE}/scripts/install_production.sh" ]]; then
  echo "ERROR: no se encontro el instalador interno."
  echo "Verifica que el ZIP v0.6 este completo en la raiz del repositorio."
  exit 1
fi

echo "[2/5] Instalando la aplicacion..."
cd "$APP_SOURCE"
./scripts/install_production.sh

echo "[3/5] Instalando Caddy..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
apt-get update -y
apt-get install -y caddy

echo "[4/5] Configurando HTTPS si el DNS ya apunta a ${SERVER_IP}..."
RESOLVED_IP="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1 {print $1}' || true)"
if [[ "$RESOLVED_IP" == "$SERVER_IP" ]]; then
  cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN} {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8080
    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
}
EOF
  caddy validate --config /etc/caddy/Caddyfile
  systemctl enable caddy
  systemctl restart caddy
  echo "DNS coincide. Caddy solicitara el certificado HTTPS automaticamente."
else
  echo "AVISO: ${DOMAIN} aun no resuelve a ${SERVER_IP} (resultado: ${RESOLVED_IP:-sin registro})."
  echo "La aplicacion quedo instalada. Configura el registro DNS A y luego activaremos HTTPS."
fi

echo "[5/5] Creando el administrador inicial..."
set -a
source /etc/pepedroid/pepedroid.env
set +a
runuser -u pepedroid -- env \
  FLASK_SECRET_KEY="$FLASK_SECRET_KEY" \
  DATABASE_URL="$DATABASE_URL" \
  COOKIE_SECURE="${COOKIE_SECURE:-1}" \
  /opt/pepedroid/venv/bin/flask --app /opt/pepedroid/manage.py create-admin

echo
echo "PEPEDROID instalado."
echo "Estado: systemctl status pepedroid --no-pager"
echo "Registros: journalctl -u pepedroid -n 50 --no-pager"
echo "No abras el puerto 8080 al publico; Caddy usa 127.0.0.1:8080."

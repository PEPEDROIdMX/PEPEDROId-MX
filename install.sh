#!/usr/bin/env bash
set -Eeuo pipefail

REPO="PEPEDROIdMX/PEPEDROID"
ARCHIVE="PEPEDROID-ubuntu24-deploy-0.3.zip"
DOMAIN="pepedroidmxxx.store"
SERVER_IP="78.13.10.162"
WORKDIR="/root/pepedroid-bootstrap"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta como root: sudo bash install.sh"
  exit 1
fi

if [[ "$( . /etc/os-release && echo "${ID}" )" != "ubuntu" ]]; then
  echo "Este instalador está preparado para Ubuntu. Se detectó otro sistema."
  exit 1
fi

echo "========================================"
echo "       PEPEDROID - INSTALADOR"
echo "========================================"
echo "[1/6] Instalando dependencias..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip ca-certificates gnupg

echo "[2/6] Descargando PEPEDROID..."
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
curl -fL "https://raw.githubusercontent.com/${REPO}/main/${ARCHIVE}" -o "${WORKDIR}/${ARCHIVE}"
unzip -q "${WORKDIR}/${ARCHIVE}" -d "$WORKDIR"

APP_SOURCE="${WORKDIR}/pepedroid/pepedroid"
if [[ ! -x "${APP_SOURCE}/scripts/install_production.sh" ]]; then
  echo "No se encontró el instalador interno. Revisa que el ZIP se haya subido completo."
  exit 1
fi

echo "[3/6] Instalando el administrador web..."
cd "$APP_SOURCE"
./scripts/install_production.sh

echo "[4/6] Instalando Caddy..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
apt-get update -y
apt-get install -y caddy

echo "[5/6] Comprobando DNS para ${DOMAIN}..."
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
  echo "DNS correcto. Caddy solicitará el certificado HTTPS automáticamente."
else
  echo "El DNS todavía no apunta a ${SERVER_IP} (resuelto: ${RESOLVED_IP:-sin registro})."
  echo "La aplicación quedó instalada; HTTPS se activará cuando configures el registro A."
  systemctl enable caddy
  cat > /etc/caddy/Caddyfile <<'EOF'
:8081 {
    respond "PEPEDROID instalado. Configura el DNS y ejecuta el paso SSL indicado en la guía." 200
}
EOF
  systemctl restart caddy
fi

echo "[6/6] Instalación base terminada."
echo
echo "IMPORTANTE: crea ahora el administrador con:"
echo "sudo -u pepedroid /opt/pepedroid/venv/bin/flask --app /opt/pepedroid/manage.py create-admin"
echo
echo "Comprueba el servicio con:"
echo "systemctl status pepedroid --no-pager"
echo
echo "No compartas la contraseña del administrador."
echo "El panel no debe exponerse en el puerto 8080; Caddy actúa como proxy."

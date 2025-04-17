#!/bin/bash

set -e
echo "###---> Instalador de seguridad AJTEL ----->"
echo "###---> Realizado por AJTEL Comunicaciones © 2025 MEXICO --->"
echo "🛡️ Instalando CrowdSec en Sangoma 7 con sincronización por IP pública..."

# Paso 1: Repositorio de CrowdSec
cat <<EOF > /etc/yum.repos.d/crowdsec.repo
[crowdsec]
name=crowdsec
baseurl=https://packagecloud.io/crowdsec/crowdsec/el/7/\$basearch
repo_gpgcheck=0
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/crowdsec/crowdsec/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF

# Paso 2: Instalar CrowdSec y bouncer
yum clean all
yum makecache
yum install -y crowdsec crowdsec-firewall-bouncer-iptables jq

# Paso 3: Habilitar servicios y colección Asterisk
cscli collections install crowdsecurity/asterisk
systemctl enable --now crowdsec
systemctl enable --now crowdsec-firewall-bouncer

# Paso 4: Crear directorios necesarios
mkdir -p /var/lib/crowdsec/{exports,imports}
mkdir -p /etc/crowdsec/config

# Paso 5: Crear whitelist de AJTEL
cat <<EOF > /etc/crowdsec/config/whitelists.yaml
whitelists:
  - reason: "Trusted AJTEL nodes"
    ip:
      - 216.238.86.33
      - 216.238.76.209
      - 216.238.89.117
      - 216.238.91.96
EOF

# Paso 6: Exportar baneos (JSON válido)
cat <<'EOF' > /usr/local/bin/exportar_baneos.sh
#!/bin/bash
EXPORT_DIR="/var/lib/crowdsec/exports"
mkdir -p "$EXPORT_DIR"
TMPFILE=$(mktemp)

cscli decisions export -o json > "$TMPFILE" 2>/dev/null

if jq empty "$TMPFILE" >/dev/null 2>&1; then
    FILENAME="$EXPORT_DIR/banlist-$(hostname)-$(date +%Y%m%d%H%M).json"
    mv "$TMPFILE" "$FILENAME"
    echo "✅ Exportación correcta: $FILENAME"
else
    echo "❌ Exportación fallida: JSON inválido"
    rm -f "$TMPFILE"
fi
EOF
chmod +x /usr/local/bin/exportar_baneos.sh

# Paso 7: Importar baneos y eliminar inválidos
cat <<'EOF' > /usr/local/bin/importar_baneos.sh
#!/bin/bash
IMPORT_DIR="/var/lib/crowdsec/imports"
for FILE in "$IMPORT_DIR"/banlist-*.json; do
    [[ ! -f "$FILE" ]] && continue
    if jq empty "$FILE" >/dev/null 2>&1; then
        echo "⬅️ Importando $FILE"
        cscli decisions import -i "$FILE" && rm -f "$FILE"
    else
        echo "❌ Archivo inválido: $FILE"
        rm -f "$FILE"
    fi
done
EOF
chmod +x /usr/local/bin/importar_baneos.sh

# Paso 8: Limpiar IPs de whitelist si están baneadas
cat <<'EOF' > /usr/local/bin/limpiar_ips_whitelist.sh
#!/bin/bash
WHITELIST="/etc/crowdsec/config/whitelists.yaml"

if [ -f "$WHITELIST" ]; then
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$WHITELIST" | while read ip; do
        cscli decisions delete --ip "$ip" >/dev/null 2>&1 && echo "🧼 Eliminada IP whitelisteada: $ip"
    done
else
    echo "⚠️ No se encontró el archivo de whitelist"
fi
EOF
chmod +x /usr/local/bin/limpiar_ips_whitelist.sh

# Paso 9: Importar IPs bloqueadas en iptables (con duración prolongada)
cat <<'EOF' > /usr/local/bin/importar-iptables-estaticas.sh
#!/bin/bash
DURACION="876000h"
IPTABLES_FILE="/etc/sysconfig/iptables"
WHITELIST_IPS=(216.238.86.33 216.238.76.209 216.238.89.117 216.238.91.96)

grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$IPTABLES_FILE" | sort -u | while read ip; do
  if [[ " ${WHITELIST_IPS[*]} " =~ " $ip " ]]; then
    echo "🟡 $ip está en whitelist, omitiendo..."
    continue
  fi
  echo "🚫 Importando IP permanente: $ip"
  cscli decisions add --ip "$ip" --reason "iptables import" --duration "$DURACION"
done
EOF
chmod +x /usr/local/bin/importar-iptables-estaticas.sh

# Paso 10: Sync whitelist a todos los nodos
cat <<'EOF' > /usr/local/bin/sync_whitelist.sh
#!/bin/bash
WHITELIST="/etc/crowdsec/config/whitelists.yaml"
REMOTE_PATH="/etc/crowdsec/config/whitelists.yaml"

declare -A DESTINOS=(
    ["216.238.91.96"]=26057
    ["216.238.86.33"]=26057
    ["216.238.89.117"]=49365
    ["216.238.76.209"]=49365
)

IP_LOCAL=$(curl -s https://ipinfo.io/ip)

for NODE in "${!DESTINOS[@]}"; do
    PORT="${DESTINOS[$NODE]}"
    if [[ "$NODE" != "$IP_LOCAL" ]]; then
        echo "📤 Enviando whitelist a $NODE:$PORT"
        scp -P "$PORT" -o StrictHostKeyChecking=no "$WHITELIST" root@$NODE:"$REMOTE_PATH"
        ssh -p "$PORT" root@$NODE "systemctl restart crowdsec"
        grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$WHITELIST" | while read ip; do
          ssh -p "$PORT" root@$NODE "cscli decisions delete --ip $ip >/dev/null 2>&1"
        done
        echo "✅ Whitelist sincronizada en $NODE"
    fi
done
EOF
chmod +x /usr/local/bin/sync_whitelist.sh

# Paso 11: Cronjobs
cat <<EOF > /etc/cron.d/crowdsec-ajtel
*/5 * * * * root /usr/local/bin/exportar_baneos.sh
*/5 * * * * root /usr/local/bin/importar_baneos.sh
15 * * * * root /usr/local/bin/importar-iptables-estaticas.sh
30 * * * * root /usr/local/bin/limpiar_ips_whitelist.sh
45 * * * * root /usr/local/bin/sync_whitelist.sh
EOF
chmod 644 /etc/cron.d/crowdsec-ajtel

# 🎉 Final
echo ""
echo "✅ Instalación y sincronización completa de seguridad AJTEL"
echo "🔐 Claves SSH deben estar listas entre nodos"
echo "📦 Archivos de IPtables importados"
echo "🔁 Whitelist protegida y sincronizada"
echo "⏱️ Revisa logs y usa '/usr/local/bin/verificar_sync.sh' para checar estado"

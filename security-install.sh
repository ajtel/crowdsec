#!/bin/bash

set -e
echo "###---> Instalador de seguridad AJTEL ----->"
echo "###---> Realizado por AJTEL Comunicaciones © 2025 MEXICO --->"
echo "🛡️ Instalando CrowdSec en Sangoma 7 con sincronización por IP pública..."

# Paso 1: Agregar repo de CrowdSec
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
yum install -y crowdsec crowdsec-firewall-bouncer-iptables

# Paso 3: Instalar colección Asterisk y habilitar servicios
cscli collections install crowdsecurity/asterisk
systemctl enable --now crowdsec
systemctl enable --now crowdsec-firewall-bouncer

# Paso 4: Crear carpetas de sincronización
mkdir -p /var/lib/crowdsec/exports
mkdir -p /var/lib/crowdsec/imports
mkdir -p /etc/crowdsec/config

# Paso 5: Crear whitelist con IPs AJTEL
cat <<EOF > /etc/crowdsec/config/whitelists.yaml
whitelists:
  - reason: "Trusted AJTEL nodes"
    ip:
      - "216.238.86.33"   # mercurio
      - "216.238.76.209"  # dedicated11
      - "216.238.89.117"  # soho1
      - "216.238.91.96"   # dedicated12
EOF

# Paso 6: Script para exportar baneos
cat <<'EOF' > /usr/local/bin/exportar_baneos.sh
#!/bin/bash
EXPORT_DIR="/var/lib/crowdsec/exports"
mkdir -p "$EXPORT_DIR"
FILENAME="$EXPORT_DIR/banlist-$(hostname)-$(date +%Y%m%d%H%M).json"

cscli decisions export -o json > "$FILENAME"

declare -A DESTINOS
DESTINOS["216.238.91.96"]=26057
DESTINOS["216.238.86.33"]=26057
DESTINOS["216.238.89.117"]=49365
DESTINOS["216.238.76.209"]=49365

IP_LOCAL=$(curl -s https://ipinfo.io/ip)

for NODE in "${!DESTINOS[@]}"; do
    if [[ "$NODE" != "$IP_LOCAL" ]]; then
        PORT="${DESTINOS[$NODE]}"
        echo "➡️ Enviando baneos a $NODE:$PORT"
        scp -P "$PORT" -o StrictHostKeyChecking=no "$FILENAME" root@$NODE:/var/lib/crowdsec/imports/
    fi
done
EOF

chmod +x /usr/local/bin/exportar_baneos.sh

# Paso 7: Script para importar baneos
cat <<'EOF' > /usr/local/bin/importar_baneos.sh
#!/bin/bash
IMPORT_DIR="/var/lib/crowdsec/imports"
for FILE in $IMPORT_DIR/banlist-*.json; do
    [ -f "$FILE" ] || continue
    echo "⬅️ Importando $FILE"
    cscli decisions import -i "$FILE"
    rm -f "$FILE"
done
EOF

chmod +x /usr/local/bin/importar_baneos.sh

# Paso 8: Script para limpiar IPs whitelisteadas activas
cat <<'EOF' > /usr/local/bin/limpiar_ips_whitelist.sh
#!/bin/bash
WHITELIST="/etc/crowdsec/config/whitelists.yaml"

if [ -f "$WHITELIST" ]; then
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$WHITELIST" | while read ip; do
        cscli decisions delete --ip "$ip" >/dev/null 2>&1 && echo "🧼 Eliminada IP whitelisteada: $ip"
    done
else
    echo "⚠️ No se encontró $WHITELIST"
fi
EOF

chmod +x /usr/local/bin/limpiar_ips_whitelist.sh

# Paso 9: Programar todos los cronjobs necesarios
cat <<EOF > /etc/cron.d/crowdsec-ajtel
*/5 * * * * root /usr/local/bin/exportar_baneos.sh
*/5 * * * * root /usr/local/bin/importar_baneos.sh
15 * * * * root /usr/local/bin/limpiar_ips_whitelist.sh
EOF

chmod 644 /etc/cron.d/crowdsec-ajtel

# ✅ Fin del proceso
echo "✅ CrowdSec, sincronización y protección de nodos AJTEL completa."
echo "📌 Todos los cronjobs fueron instalados:"
echo "    - Exportación/importación cada 5 min"
echo "    - Limpieza de whitelist cada hora"
echo "🚀 Listo para sincronizar entre:"
echo "    - mercurio.ajtel.net"
echo "    - soho1.ajtel.net"
echo "    - dedicated11.ajtel.net"
echo "    - dedicated12.ajtel.net"

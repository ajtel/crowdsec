#!/bin/bash

set -e

echo "🛡️ Instalando CrowdSec en Sangoma 7 con sincronización por IP pública..."

# Paso 1: Agregar repo de CrowdSec (para CentOS 7/Sangoma 7)
cat <<EOF | sudo tee /etc/yum.repos.d/crowdsec.repo
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

# Paso 3: Instalar colección para Asterisk
cscli collections install crowdsecurity/asterisk
systemctl enable --now crowdsec
systemctl enable --now crowdsec-firewall-bouncer

# Paso 4: Crear directorios para sincronización
mkdir -p /var/lib/crowdsec/exports
mkdir -p /var/lib/crowdsec/imports

# Paso 5: Script exportador actualizado
cat <<'EOF' > /usr/local/bin/exportar_baneos.sh
#!/bin/bash

EXPORT_DIR="/var/lib/crowdsec/exports"
mkdir -p "$EXPORT_DIR"
FILENAME="$EXPORT_DIR/banlist-$(hostname)-$(date +%Y%m%d%H%M).json"

# Exportar IPs baneadas en formato JSON
cscli decisions export -o json > "$FILENAME"

# Mapa de IPs públicas y puertos SSH personalizados
declare -A DESTINOS
DESTINOS["216.238.91.96"]=26057    # dedicated12
DESTINOS["216.238.86.33"]=26057    # mercurio
DESTINOS["216.238.89.117"]=49365   # soho1
DESTINOS["216.238.76.209"]=49365   # dedicated11

IP_LOCAL=$(curl -s https://ipinfo.io/ip)

for NODE in "${!DESTINOS[@]}"; do
    if [[ "$NODE" != "$IP_LOCAL" ]]; then
        PORT="${DESTINOS[$NODE]}"
        echo "➡️ Enviando baneos a $NODE:$PORT"
        scp -P "$PORT" -o StrictHostKeyChecking=no "$FILENAME" root@$NODE:/var/lib/crowdsec/imports/
    else
        echo "🛑 Saltando IP local $NODE ($PORT)"
    fi
done
EOF

chmod +x /usr/local/bin/exportar_baneos.sh

# Paso 6: Script importador
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

# Paso 7: Cronjob para sincronización
cat <<EOF > /etc/cron.d/crowdsec-sync
*/5 * * * * root /usr/local/bin/exportar_baneos.sh
*/5 * * * * root /usr/local/bin/importar_baneos.sh
EOF

chmod 644 /etc/cron.d/crowdsec-sync

echo "✅ CrowdSec instalado y sincronización por IP pública activa."
echo "📌 Asegúrate de que los puertos SSH estén abiertos entre nodos y se hayan distribuido las claves con ssh-copy-id."

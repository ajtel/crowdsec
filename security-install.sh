##########--->AJTEL COMUNICACIONES MEXICO<-----
##########--->INSTALACION DE SISTEMA DE SEGURIDAD INTERNO PARA RED XVLAN<-----

#!/bin/bash

set -e

echo "🛡️ Instalando CrowdSec en Sangoma 7..."

# Paso 1: Agregar repo manualmente (como CentOS 7)
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

# Paso 2: Instalar CrowdSec y el bouncer
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

# Paso 5: Crear script exportador
cat <<'EOF' > /usr/local/bin/exportar_baneos.sh
#!/bin/bash
EXPORT_DIR="/var/lib/crowdsec/exports"
mkdir -p "$EXPORT_DIR"
FILENAME="$EXPORT_DIR/banlist-$(hostname)-$(date +%Y%m%d%H%M).json"
cscli decisions export -o json > "$FILENAME"
DESTINOS=("10.42.96.3" "10.42.96.4" "10.42.96.6" "10.42.96.7")
IP_LOCAL=$(hostname -I | awk '{print $1}')
for NODE in "${DESTINOS[@]}"; do
    if [[ "$NODE" != "$IP_LOCAL" ]]; then
        scp -o StrictHostKeyChecking=no "$FILENAME" root@$NODE:/var/lib/crowdsec/imports/
    fi
done
EOF

chmod +x /usr/local/bin/exportar_baneos.sh

# Paso 6: Crear script importador
cat <<'EOF' > /usr/local/bin/importar_baneos.sh
#!/bin/bash
IMPORT_DIR="/var/lib/crowdsec/imports"
for FILE in $IMPORT_DIR/banlist-*.json; do
    [ -f "$FILE" ] || continue
    cscli decisions import -i "$FILE"
    rm -f "$FILE"
done
EOF

chmod +x /usr/local/bin/importar_baneos.sh

# Paso 7: Crear cronjob central
cat <<EOF > /etc/cron.d/crowdsec-sync
*/5 * * * * root /usr/local/bin/exportar_baneos.sh
*/5 * * * * root /usr/local/bin/importar_baneos.sh
EOF

chmod 644 /etc/cron.d/crowdsec-sync

echo "✅ CrowdSec instalado y sincronización habilitada entre nodos."
echo "📌 Asegúrate de distribuir claves SSH entre los nodos para permitir scp sin contraseña."

#!/bin/bash
set -e

echo "###---> Instalador de seguridad AJTEL ----->"
echo "###---> Realizado por AJTEL Comunicaciones © 2025 MEXICO --->"
echo "🛡️ Instalando CrowdSec y herramientas defensivas..."

# 1. Repositorio de CrowdSec
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

# 2. Instalar paquetes necesarios
yum clean all
yum makecache
yum install -y epel-release
yum install -y crowdsec crowdsec-firewall-bouncer-iptables jq mysql mariadb

# 3. Configurar servicios y colecciones
cscli collections install crowdsecurity/asterisk
systemctl enable --now crowdsec
systemctl enable --now crowdsec-firewall-bouncer

# 4. Directorios necesarios
mkdir -p /var/lib/crowdsec/{exports,imports}
mkdir -p /etc/crowdsec/config

# 5. Whitelist AJTEL
cat <<EOF > /etc/crowdsec/config/whitelists.yaml
whitelists:
  - reason: "Trusted AJTEL nodes"
    ip:
      - 216.238.86.33
      - 216.238.76.209
      - 216.238.89.117
      - 216.238.91.96
EOF

# 6. Scripts de sincronización
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/exportar_baneos.sh -o /usr/local/bin/exportar_baneos.sh
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/importar_baneos.sh -o /usr/local/bin/importar_baneos.sh
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/limpiar_ips_whitelist.sh -o /usr/local/bin/limpiar_ips_whitelist.sh
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/sync_whitelist.sh -o /usr/local/bin/sync_whitelist.sh
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/importar-iptables-estaticas.sh -o /usr/local/bin/importar-iptables-estaticas.sh
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/importar_fail2ban.sh -o /usr/local/bin/importar_fail2ban.sh
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/importar_firewall_fpbx.sh -o /usr/local/bin/importar_firewall_fpbx.sh
curl -sL https://raw.githubusercontent.com/ajtelmexico/crowdsec-ajtel/main/bin/verificar_sync.sh -o /usr/local/bin/verificar_sync.sh

chmod +x /usr/local/bin/*.sh

# 7. Cron completo
cat <<EOF > /etc/cron.d/crowdsec-ajtel
*/5 * * * * root /usr/local/bin/exportar_baneos.sh
*/5 * * * * root /usr/local/bin/importar_baneos.sh
10 * * * * root /usr/local/bin/limpiar_ips_whitelist.sh
15 * * * * root /usr/local/bin/importar-iptables-estaticas.sh
*/10 * * * * root /usr/local/bin/importar_fail2ban.sh
*/15 * * * * root /usr/local/bin/importar_firewall_fpbx.sh
30 * * * * root /usr/local/bin/sync_whitelist.sh
5 * * * * root /usr/local/bin/verificar_sync.sh
EOF

chmod 644 /etc/cron.d/crowdsec-ajtel
systemctl restart crond

# 8. Final
echo ""
echo "✅ Seguridad AJTEL desplegada correctamente"
echo "📌 Revisa /etc/cron.d/crowdsec-ajtel para tareas"
echo "📤 Exportar, importar, limpiar, sync... ¡todo listo!"
echo "📲 Notificaciones configurables vía Telegram"
echo "🔁 Verifica estado con: /usr/local/bin/verificar_sync.sh"

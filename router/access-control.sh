#si algo falla entonces el script se detiene
set -euo pipefail

# Archivos de configuracion
CONF_DIR="/root/r1"
VLAN_FILE="$CONF_DIR/VLANs.conf"
MAC_FILE="$CONF_DIR/access.mac"
IP_FILE="$CONF_DIR/access.ip"

# Interfaz hacia el load balancer
WAN_IFACE="enx00e04c360117"


# Leer interfaces LAN desde VLANs.conf 


# Esta línea usa 'awk' para analizar el archivo de VLANs y construir una lista (array) con todas las interfaces LAN.
# Ignora líneas vacías o de comentario (#)
# Omite la primera columna (ID de la VLAN)
# Extrae todas las interfaces definidas a partir de la segunda columna
LAN_IFACES=($(awk 'NF>1 && $1 !~ /^#/ { for (i=2; i<=NF; i++) print $i }' "$VLAN_FILE"))

# Cargar listas de IPs y MACs permitidas
ALLOWED_MACS=($(cat "$MAC_FILE"))
ALLOWED_IPS=($(cat "$IP_FILE"))

echo "[R1] Aplicando política 'todo cerrado'..."
echo "[R1] Interfaces LAN: ${LAN_IFACES[*]}"
echo "[R1] Interfaz WAN: ${WAN_IFACE}"
echo "[R1] MACs permitidas: ${#ALLOWED_MACS[@]}"
echo "[R1] IPs permitidas: ${#ALLOWED_IPS[@]}"

# Limpia las reglas anteriores

iptables -F
iptables -t nat -F
iptables -X

# Políticas por defecto

iptables -P INPUT DROP       # Bloquea por defecto todo el tráfico que entra al router.
iptables -P FORWARD DROP     # Bloquea por defecto todo el tráfico que pasa a través del router.
iptables -P OUTPUT ACCEPT    # Permite que el propio router acceda a Internet

# Permitir tráfico local y conexiones establecidas

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- Permitir ICMP (ping) desde las VLANs internas hacia el router ---
# Esto permite que los clientes de las VLANs (por ejemplo 192.168.20.2, .3, etc.)
# puedan hacer ping al router para verificar conectividad.
# No afecta la seguridad ni abre otros servicios.
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT


# --- Permitir acceso total desde la VLAN de Administración (VLAN 10) ---
# Todo el tráfico proveniente de la VLAN 10 (enp1s0.10) se permite completamente.
# Los administradores pueden acceder a Zabbix, WordPress admin y toda la red interna.
iptables -A INPUT -i enp1s0.10 -j ACCEPT
iptables -A FORWARD -i enp1s0.10 -j ACCEPT


# Permitir consultas DNS hacia R1
# Los clientes de las VLANs podrán usar al router como servidor DNS
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -j ACCEPT


# Recorre todas las interfaces del archivo Vlans.conf y permite su trafico

#for IFACE in "${LAN_IFACES[@]}"; do
 # iptables -A INPUT -i "$IFACE" -j ACCEPT
#done


# Permitir tráfico hacia Internet si la IP está en la lista 


# Este bloque permite que únicamente las direcciones IP escritas en el archivo access.ip
# puedan salir a Internet a través del router.
# Ya no recorre las interfaces LAN: las reglas aplican para cualquier red interna.
# Por cada IP autorizada se agrega una regla que permite su tráfico saliente (FORWARD).
for IP in "${ALLOWED_IPS[@]}"; do
  # Permite reenviar (FORWARD) el tráfico saliente desde la IP autorizada
  # hacia la interfaz WAN 
  iptables -A FORWARD -o "$WAN_IFACE" -s "$IP" -j ACCEPT
done  


# Permitir tráfico hacia Internet si la MAC está en la lista


# Este bloque permite que únicamente los equipos cuyas direcciones MAC estén escritas
# en el archivo access.mac puedan salir a Internet.
# Ya no se recorren las interfaces LAN: las reglas aplican para cualquier red interna.
# Por cada MAC autorizada se agrega una regla que permite su tráfico saliente (FORWARD).

for MAC in "${ALLOWED_MACS[@]}"; do
  # Permite reenviar (FORWARD) el tráfico que provenga de una dirección MAC permitida
  # hacia la interfaz WAN (enlace al firewall o Internet).
  iptables -A FORWARD -o "$WAN_IFACE" -m mac --mac-source "$MAC" -j ACCEPT
done


#  Habilitar NAT
iptables -t nat -A POSTROUTING -o "$WAN_IFACE" -j MASQUERADE

#  Bloquear todo lo demás
iptables -A FORWARD -j DROP

echo "[R1] Reglas aplicadas exitosamente (IP O MAC permitidas)."

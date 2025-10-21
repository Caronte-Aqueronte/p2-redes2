#!/bin/bash
# ==========================================================
# auto_vlan.sh
# Script para crear automáticamente VLANs en Debian
# Lee el archivo /root/VLANs.conf
# William A. Miranda - Proyecto Router R1
# ==========================================================

CONF_FILE="/root/r1/VLANs.conf"

# Tabla de IPs asignadas por VLAN (puedes editar según tu topología)
declare -A VLAN_IPS=(
  [10]="192.168.10.1/30"
  [20]="192.168.20.1/30"
  [30]="192.168.30.1/30"
  [40]="192.168.40.1/30"
)

echo "🔧 [auto_vlan.sh] Iniciando asignación automática de VLANs..."
echo "Archivo de configuración: $CONF_FILE"

# Verificar que el archivo exista
if [ ! -f "$CONF_FILE" ]; then
  echo "❌ Error: No se encontró $CONF_FILE"
  exit 1
fi

# Activar enrutamiento IPv4 si no está activo
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
  echo "1" > /proc/sys/net/ipv4/ip_forward
  echo "🌐 Enrutamiento IPv4 habilitado."
fi

# Leer VLANs del archivo
while read -r VLAN_ID IFACES; do
  # Saltar comentarios o líneas vacías
  [[ "$VLAN_ID" =~ ^#.*$ || -z "$VLAN_ID" ]] && continue

  for IFACE in $IFACES; do
    VLAN_IFACE="${IFACE}.${VLAN_ID}"

    echo "🟢 Creando VLAN $VLAN_ID sobre $IFACE → $VLAN_IFACE"

    # Crear subinterfaz VLAN si no existe
    ip link show "$VLAN_IFACE" &>/dev/null
    if [ $? -ne 0 ]; then
      ip link add link "$IFACE" name "$VLAN_IFACE" type vlan id "$VLAN_ID"
      echo "   VLAN $VLAN_ID creada exitosamente."
    else
      echo "   VLAN $VLAN_IFACE ya existe, saltando..."
    fi

    # Asignar IP si está definida
    if [[ -n "${VLAN_IPS[$VLAN_ID]}" ]]; then
      ip addr flush dev "$VLAN_IFACE" 2>/dev/null
      ip addr add "${VLAN_IPS[$VLAN_ID]}" dev "$VLAN_IFACE"
      echo "   IP asignada: ${VLAN_IPS[$VLAN_ID]}"
    else
      echo "   (Sin IP definida para VLAN $VLAN_ID)"
    fi

    # Activar interfaz
    ip link set "$VLAN_IFACE" up
  done
done < "$CONF_FILE"

echo "✅ Configuración de VLANs completada."

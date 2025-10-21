#!/usr/bin/env bash

# ==== AJUSTA ESTOS CUATRO VALORES ====
IFACE_PRIMARY="enx00e04c360afb"      # interfaz/cable principal
GW_PRIMARY="10.10.30.1"     # gateway (o IP del otro PC) por ese cable

IFACE_SECONDARY="enx9c69d310c086"    # interfaz/cable de respaldo
GW_SECONDARY="10.10.30.5"   # gateway (o IP del otro PC) por ese cable
# =====================================

# RUTA ACTUAL
CURRENT="none"

while true; do
  # Pings
  ping -I "$IFACE_PRIMARY" -c1 -W1 "$GW_PRIMARY" >/dev/null 2>&1
  STATUS1=$?
  ping -I "$IFACE_SECONDARY" -c1 -W1 "$GW_SECONDARY" >/dev/null 2>&1
  STATUS2=$?

  # Mostrar estado de ambos enlaces
  echo -n "$(date '+%H:%M:%S') | "
  if [ $STATUS1 -eq 0 ]; then
    echo -n "[OK] $IFACE_PRIMARY ($GW_PRIMARY) "
  else
    echo -n "[DOWN] $IFACE_PRIMARY ($GW_PRIMARY) "
  fi

  if [ $STATUS2 -eq 0 ]; then
    echo -n "| [OK] $IFACE_SECONDARY ($GW_SECONDARY)"
  else
    echo -n "| [DOWN] $IFACE_SECONDARY ($GW_SECONDARY)"
  fi
  echo ""

  # Cambiar ruta por defecto según disponibilidad
  if [ $STATUS1 -eq 0 ]; then
    if [ "$CURRENT" != "primary" ]; then
      ip route replace default via "$GW_PRIMARY" dev "$IFACE_PRIMARY"
      CURRENT="primary"
      echo "→ Ruta cambiada al PRIMARIO ($GW_PRIMARY)"
    fi
  elif [ $STATUS2 -eq 0 ]; then
    if [ "$CURRENT" != "secondary" ]; then
      ip route replace default via "$GW_SECONDARY" dev "$IFACE_SECONDARY"
      CURRENT="secondary"
      echo "→ Ruta cambiada al SECUNDARIO ($GW_SECONDARY)"
    fi
  else
    echo "⚠️  Ambos enlaces caídos"
    CURRENT="none"
  fi

  sleep 3
done


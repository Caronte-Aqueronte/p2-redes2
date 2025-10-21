#!/usr/bin/env bash

# === TUS VALORES ===
IFACE_PRIMARY="enx00e04c360afb"
GW_PRIMARY="10.10.30.1"
IFACE_SECONDARY="enx9c69d310c086"
GW_SECONDARY="10.10.30.5"
# ===================

BWD_FILE="/opt/lb/bandwidth.conf"
NFT_TABLE="inet lb"
NFT_CHAIN="mangle"

CURRENT="none"

# Lee pesos para mostrar
W1=1; W2=1
if [ -f "$BWD_FILE" ]; then
  while IFS=, read -r isp up dw; do
    isp=$(echo "$isp" | xargs | tr a-z A-Z)
    up=$(echo "$up" | xargs); dw=$(echo "$dw" | xargs)
    case "$isp" in
      ISP1) W1="${dw:-$up}";;
      ISP2) W2="${dw:-$up}";;
    esac
  done < <(grep -Ev '^\s*(#|$)' "$BWD_FILE")
fi

while true; do
  # Salud enlaces
  ping -I "$IFACE_PRIMARY"   -c1 -W1 "$GW_PRIMARY"   >/dev/null 2>&1; S1=$?
  ping -I "$IFACE_SECONDARY" -c1 -W1 "$GW_SECONDARY" >/dev/null 2>&1; S2=$?

  # Ruta por defecto actual
  DEF=$(ip route show default 2>/dev/null | head -n1 | sed 's/^default //')

  # Cabecera de estado
  echo "----- $(date '+%F %T') -----"
  printf "Enlace1: %s %s (%s)\n" "$([ $S1 -eq 0 ] && echo OK || echo DOWN)" "$IFACE_PRIMARY" "$GW_PRIMARY"
  printf "Enlace2: %s %s (%s)\n" "$([ $S2 -eq 0 ] && echo OK || echo DOWN)" "$IFACE_SECONDARY" "$GW_SECONDARY"
  echo "Default route: $DEF"
  echo "ECMP (bandwidth.conf): ISP1=$W1  ISP2=$W2"

  # Contadores de reglas nftables
  if nft list chain "$NFT_TABLE" "$NFT_CHAIN" >/dev/null 2>&1; then
    echo "Counters:"
    # muestra cada regla con su contador
    nft list chain "$NFT_TABLE" "$NFT_CHAIN" | nl -ba | sed -n 's/^\s*\([0-9]\+\)\s\+\(.*counter.*\)$/  \1) \2/p'
  else
    echo "Counters: (no chain $NFT_TABLE/$NFT_CHAIN)"
  fi

  # Failover de la default route (simple)
  if [ $S1 -eq 0 ]; then
    if [ "$CURRENT" != "primary" ]; then
      ip route replace default via "$GW_PRIMARY" dev "$IFACE_PRIMARY"
      CURRENT="primary"
      echo "→ Ruta cambiada al PRIMARIO ($GW_PRIMARY)"
    fi
  elif [ $S2 -eq 0 ]; then
    if [ "$CURRENT" != "secondary" ]; then
      ip route replace default via "$GW_SECONDARY" dev "$IFACE_SECONDARY"
      CURRENT="secondary"
      echo "→ Ruta cambiada al SECUNDARIO ($GW_SECONDARY)"
    fi
  else
    echo "⚠️  Ambos enlaces caídos (no se cambia ruta)."
    CURRENT="none"
  fi

  echo
  sleep 3
done


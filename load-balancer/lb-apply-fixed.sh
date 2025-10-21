#!/usr/bin/env bash
set -euo pipefail
set +o braceexpand

# ========= Interfaces (solo para NAT opcional) =========
WAN1="enx00e04c360afb"   # ISP1
WAN2="enx9c69d310c086"   # ISP2
ENABLE_NAT=0             # 1 = agrega MASQUERADE por WAN; 0 = no toca NAT
# =======================================================

BWD_FILE="/opt/lb/bandwidth.conf"
RULES_FILE="/opt/lb/LB_rules.conf"

# Marcas lógicas (solo para contadores/clasificación)
MARK_ISP1=0x1
MARK_ISP2=0x2

NFT_TABLE="inet lb"
NFT_CHAIN="mangle"     # hook prerouting priority mangle
NFT_POSTNAT="postnat"  # NAT opcional

echo "[lb-apply] Limpiando tabla nft anterior (solo nft)…"
nft list table "$NFT_TABLE" >/dev/null 2>&1 && nft delete table "$NFT_TABLE"

echo "[lb-apply] Creando tabla/cadenas nft…"
nft add table "$NFT_TABLE"
nft add chain "$NFT_TABLE" "$NFT_CHAIN" '{ type filter hook prerouting priority mangle; policy accept; }'

if [ "$ENABLE_NAT" -eq 1 ]; then
  nft add chain "$NFT_TABLE" "$NFT_POSTNAT" '{ type nat hook postrouting priority 100; policy accept; }'
  nft add rule "$NFT_TABLE" "$NFT_POSTNAT" oifname "$WAN1" masquerade
  nft add rule "$NFT_TABLE" "$NFT_POSTNAT" oifname "$WAN2" masquerade
  echo "[lb-apply] NAT habilitado (masquerade por $WAN1 y $WAN2)."
else
  echo "[lb-apply] NAT deshabilitado (ENABLE_NAT=0)."
fi

# ---- Parser de LB_rules.conf: "SRC, [p1,p2], PROTO, ISPx" ----
parse_rule_line() {
  local line="$1"
  line="$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "$line" =~ ^([^,]+)[[:space:]]*,[[:space:]]*\[([0-9[:space:],]+)\][[:space:]]*,[[:space:]]*([A-Za-z]+)[[:space:]]*,[[:space:]]*(ISP[12])[[:space:]]*$ ]]; then
    local src="${BASH_REMATCH[1]}"
    local ports_set="$(echo "${BASH_REMATCH[2]}" | tr -d ' ')"
    local proto="$(echo "${BASH_REMATCH[3]}" | tr '[:lower:]' '[:upper:]')"
    local isp="${BASH_REMATCH[4]}"
    echo "${src}|${ports_set}|${proto}|${isp}"
    return 0
  fi
  return 1
}

echo "[lb-apply] Cargando reglas desde $RULES_FILE…"
if [ -f "$RULES_FILE" ]; then
  while IFS= read -r rawline; do
    [[ -z "$rawline" || "$rawline" =~ ^[[:space:]]*# ]] && continue
    if ! parsed="$(parse_rule_line "$rawline")"; then
      echo "[WARN] Línea inválida: $rawline"
      continue
    fi
    src="${parsed%%|*}"; rest="${parsed#*|}"
    ports_set="${rest%%|*}"; rest="${rest#*|}"
    proto="${rest%%|*}"; isp="${rest#*|}"

    case "$proto" in
      TCP) proto_expr="ip protocol tcp tcp dport { $ports_set }" ;;
      UDP) proto_expr="ip protocol udp udp dport { $ports_set }" ;;
      *)   echo "[WARN] Protocolo inválido: $proto"; continue ;;
    esac
    case "$isp" in
      ISP1) mark=$MARK_ISP1 ;;
      ISP2) mark=$MARK_ISP2 ;;
      *)    echo "[WARN] ISP inválido: $isp"; continue ;;
    esac

    # Regla: si el origen coincide y el puerto/proto coincide → set mark (para contadores/clasificación)
    nft add rule "$NFT_TABLE" "$NFT_CHAIN" ip saddr "$src" $proto_expr meta mark set $mark counter
    echo "  + $src $proto [$ports_set] → $isp"
  done < "$RULES_FILE"
else
  echo "[lb-apply] (No existe $RULES_FILE; solo defaults)"
fi

echo "[lb-apply] Reglas por defecto:"
# HTTP/HTTPS → ISP1
nft add rule "$NFT_TABLE" "$NFT_CHAIN" ip protocol tcp tcp dport {80,443} meta mark set $MARK_ISP1 counter
echo "  + default TCP [80,443] → ISP1"
# Resto → ISP2
nft add rule "$NFT_TABLE" "$NFT_CHAIN" meta mark != $MARK_ISP1 meta mark set $MARK_ISP2 counter
echo "  + default resto → ISP2"

# Solo leemos pesos para mostrarlos (NO tocamos rutas)
if [ -f "$BWD_FILE" ]; then
  W1=1; W2=1
  while IFS=, read -r isp up dw; do
    [[ -z "$isp" || "$isp" =~ ^[[:space:]]*# ]] && continue
    isp="$(echo "$isp" | xargs | tr '[:lower:]' '[:upper:]')"
    up="$(echo "$up" | xargs)"; dw="$(echo "$dw" | xargs)"
    case "$isp" in
      ISP1) W1="${dw:-$up}";;
      ISP2) W2="${dw:-$up}";;
    esac
  done < "$BWD_FILE"
  echo "[lb-apply] Pesos leídos (bandwidth.conf): ISP1=$W1 ISP2=$W2 (informativo; no se cambia la ruta)."
else
  echo "[lb-apply] (No existe $BWD_FILE; sin pesos)"
fi

echo "[lb-apply] Hecho. (No se modificó la ruta por defecto ni policy routing)"

#!/usr/bin/env bash
set -euo pipefail
# Desactiva brace expansion para poder usar { } sin escapes en nft
set +o braceexpand

# === TUS INTERFACES / GATEWAYS ===
WAN1="enx00e04c360afb"; GW1="10.10.30.1"    # ISP1
WAN2="enx9c69d310c086"; GW2="10.10.30.5"    # ISP2
# =================================

BWD_FILE="/opt/lb/bandwidth.conf"
RULES_FILE="/opt/lb/LB_rules.conf"

MARK_ISP1=0x1
MARK_ISP2=0x2
TABLE_ISP1=100
TABLE_ISP2=200
NFT_TABLE="inet lb"
NFT_CHAIN="mangle"

echo "[lb-apply] Limpiando configuraciones previas..."
ip rule del fwmark $MARK_ISP1 table $TABLE_ISP1 2>/dev/null || true
ip rule del fwmark $MARK_ISP2 table $TABLE_ISP2 2>/dev/null || true
ip route flush table $TABLE_ISP1 2>/dev/null || true
ip route flush table $TABLE_ISP2 2>/dev/null || true
nft list table "$NFT_TABLE" >/dev/null 2>&1 && nft delete table "$NFT_TABLE"

echo "[lb-apply] Policy routing (tablas 100/200)..."
ip rule add fwmark $MARK_ISP1 table $TABLE_ISP1
ip rule add fwmark $MARK_ISP2 table $TABLE_ISP2
ip route replace table $TABLE_ISP1 default via "$GW1" dev "$WAN1"
ip route replace table $TABLE_ISP2 default via "$GW2" dev "$WAN2"

echo "[lb-apply] nftables (marcado por reglas)..."
nft add table $NFT_TABLE
nft add chain $NFT_TABLE $NFT_CHAIN '{ type filter hook prerouting priority mangle; policy accept; }'

# ------- Parser de líneas "SRC, [p1,p2,...], PROTO, ISPx" -------
parse_rule_line() {
  # Entrada: línea completa
  # Salida (echo): src|ports_set|proto|isp   con puertos como "443,80"
  local line="$1"
  line="$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"

  if [[ "$line" =~ ^([^,]+)[[:space:]]*,[[:space:]]*\[([0-9[:space:],]+)\][[:space:]]*,[[:space:]]*([A-Za-z]+)[[:space:]]*,[[:space:]]*(ISP[12])[[:space:]]*$ ]]; then
    local src="${BASH_REMATCH[1]}"
    local ports_set="${BASH_REMATCH[2]}"
    local proto="${BASH_REMATCH[3]}"
    local isp="${BASH_REMATCH[4]}"
    ports_set="$(echo "$ports_set" | tr -d ' ')"   # deja "443,80"
    echo "${src}|${ports_set}|${proto}|${isp}"
    return 0
  else
    return 1
  fi
}
# -----------------------------------------------------------------

echo "[lb-apply] Reglas específicas desde LB_rules.conf..."
if [ -f "$RULES_FILE" ]; then
  while IFS= read -r rawline; do
    [[ -z "$rawline" || "$rawline" =~ ^[[:space:]]*# ]] && continue

    if ! parsed="$(parse_rule_line "$rawline")"; then
      echo "[WARN] Línea inválida (formato): $rawline"
      continue
    fi

    src="${parsed%%|*}"; rest="${parsed#*|}"
    ports_set="${rest%%|*}"; rest="${rest#*|}"
    proto="${rest%%|*}"; isp="${rest#*|}"

    proto_up="$(echo "$proto" | tr '[:lower:]' '[:upper:]')"
    case "$proto_up" in
      TCP) proto_expr="ip protocol tcp tcp dport { $ports_set }" ;;
      UDP) proto_expr="ip protocol udp udp dport { $ports_set }" ;;
      *)   echo "[WARN] Protocolo inválido: $proto"; continue ;;
    esac   # <-- aquí estaba el typo antes (ahora es 'esac' correcto)

    case "$isp" in
      ISP1) mark=$MARK_ISP1 ;;
      ISP2) mark=$MARK_ISP2 ;;
      *)    echo "[WARN] ISP inválido: $isp"; continue ;;
    esac

    nft add rule $NFT_TABLE $NFT_CHAIN ip saddr "$src" $proto_expr meta mark set $mark counter
    echo "  + $src $proto_up [$ports_set] -> $isp"
  done < "$RULES_FILE"
else
  echo "[lb-apply] (No existe $RULES_FILE; se aplicarán solo defaults)"
fi

echo "[lb-apply] Reglas por defecto..."
# HTTP/HTTPS -> ISP1  (brace expansion ya desactivada)
nft add rule $NFT_TABLE $NFT_CHAIN ip protocol tcp tcp dport {80,443} meta mark set $MARK_ISP1 counter
# Resto del tráfico que aún no tenga mark -> ISP2
nft add rule $NFT_TABLE $NFT_CHAIN meta mark != $MARK_ISP1 meta mark set $MARK_ISP2 counter

echo "[lb-apply] ECMP ponderado (bandwidth.conf)..."
W1=1; W2=1
if [ -f "$BWD_FILE" ]; then
  while IFS=, read -r isp up dw; do
    isp="$(echo "$isp" | xargs | tr '[:lower:]' '[:upper:]')"
    up="$(echo "$up" | xargs)"; dw="$(echo "$dw" | xargs)"
    case "$isp" in
      ISP1) W1="${dw:-$up}";;
      ISP2) W2="${dw:-$up}";;
    esac
  done < <(grep -Ev '^\s*(#|$)' "$BWD_FILE")
else
  echo "[lb-apply] (No existe $BWD_FILE; usando pesos por defecto 1:1)"
fi

gcd() { awk -v a="${1:-1}" -v b="${2:-1}" 'function GCD(x,y){return y?GCD(y,x%y):x} BEGIN{print GCD(a,b)}'; }
G=$(gcd "$W1" "$W2"); [ "${G:-1}" -eq 0 ] && G=1
W_ISP1=$(( W1 / G )); W_ISP2=$(( W2 / G ))
[ "$W_ISP1" -le 0 ] && W_ISP1=1
[ "$W_ISP2" -le 0 ] && W_ISP2=1
echo "   Pesos normalizados: ISP1=$W_ISP1  ISP2=$W_ISP2"

echo "[lb-apply] Estableciendo default ECMP..."
ip route replace default scope global \
  nexthop via "$GW1" dev "$WAN1" weight "$W_ISP1" \
  nexthop via "$GW2" dev "$WAN2" weight "$W_ISP2"

echo "[lb-apply] Hecho."


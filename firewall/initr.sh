#!/usr/bin/env bash
set -u

add_or_replace() {
  local net="$1" gw="$2" dev="$3"
  ip route add "$net" via "$gw" dev "$dev" 2>/dev/null || \
  ip route replace "$net" via "$gw" dev "$dev"
}

# Rutas
add_or_replace 192.168.10.0/30 10.10.30.4 enx9c69d30f13c0
add_or_replace 10.10.10.0/30   10.10.30.4 enx9c69d30f13c0
add_or_replace 10.10.20.0/30   10.10.30.4 enx9c69d30f13c0

# Forward + NAT (mínimo)
sysctl -w net.ipv4.ip_forward=1 >/dev/null
iptables -t nat -C POSTROUTING -o wlp4s0 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o wlp4s0 -j MASQUERADE

echo "[initr.sh] rutas por enx9c69d30f13c0 aplicadas"

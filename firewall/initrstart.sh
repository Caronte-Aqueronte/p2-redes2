#!/usr/bin/env bash

# === RUTAS DE INTERCONEXIÓN ===
# (Interfaces: enx9c69d30f132d y enx9c69d30f13c0)

# --- Rutas por enx9c69d30f132d ---
sudo ip route add 192.168.10.0/30 via 10.10.30.2 dev enx9c69d30f132d
sudo ip route add 10.10.10.0/30  via 10.10.30.2 dev enx9c69d30f132d
sudo ip route add 10.10.20.0/30  via 10.10.30.2 dev enx9c69d30f132d

# --- Rutas por enx9c69d30f13c0 ---
#sudo ip route add 192.168.10.0/30 via 10.10.30.2 dev enx9c69d30f13c0
#sudo ip route add 10.10.10.0/30  via 10.10.30.2 dev enx9c69d30f13c0
#sudo ip route add 10.10.20.0/30  via 10.10.30.2 dev enx9c69d30f13c0

# === SALIDA A INTERNET ===
sudo iptables -t nat -A POSTROUTING -o wlp4s0 -j MASQUERADE
sudo sysctl -p

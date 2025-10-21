sudo ip route add 192.168.10.0/30 via 10.10.10.2 dev enp1s0
sudo ip route add 10.10.30.0/30 via 10.10.20.1 dev enx00e04c360131

# esta regla permite todas las LAN por R1
sudo ip route add 192.168.0.0/30 via 10.10.10.2

#esta regla permite que todo trafico que venga desde la interfaz conectada salga a internet
#sudo iptables -t nat -A POSTROUTING -o wlp2s0 -j MASQUERADE

sudo sysctl -p

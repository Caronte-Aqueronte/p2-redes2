# --- Habilitar reenvío de paquetes ---
sysctl -w net.ipv4.ip_forward=1

# Evita que los clientes (192.168.20.0/30) hagan ping o accedan a otras VLANs internas
iptables -A FORWARD -s 192.168.20.0/30 -d 192.168.10.0/30 -j DROP
iptables -A FORWARD -s 192.168.20.0/30 -d 192.168.30.0/30 -j DROP
iptables -A FORWARD -s 192.168.20.0/30 -d 192.168.40.0/30 -j DROP

# También bloquea el tráfico de vuelta desde esas redes hacia la 192.168.20.0/30
iptables -A FORWARD -s 192.168.10.0/30 -d 192.168.20.0/30 -j DROP
iptables -A FORWARD -s 192.168.30.0/30 -d 192.168.20.0/30 -j DROP
iptables -A FORWARD -s 192.168.40.0/30 -d 192.168.20.0/30 -j DROP

# Reglas de forwarding entre la vpn de hamachi -> wordpress y viceversa
#sudo iptables -A FORWARD -i ham0 -o enp1s0.40 -d 192.168.40.0/30 -j ACCEPT
#sudo iptables -A FORWARD -i enp1s0.40 -o ham0 -s 192.168.40.0/30 -j ACCEPT
#sudo iptables -t nat -A POSTROUTING -s 25.0.0.0/8 -d 192.168.40.0/30 -j MASQUERADE
#sudo iptables -t nat -A POSTROUTING -o ham0 -j MASQUERADE

# --- Rutas hacia las redes detrás del Proxy (Load Balancer) ---
ip route add 10.10.20.0/30 via 10.10.10.1 dev enx00e04c360117
ip route add 10.10.30.0/30 via 10.10.10.1 dev enx00e04c360117

sudo iptables -A INPUT -p tcp -s 192.168.20.0/30 --dport 3128 -j ACCEPT

# --- Redirigir solo tráfico HTTP hacia el Proxy ---
#iptables -t nat -A PREROUTING -i enp1s0.20 -p tcp --dport 80 -j DNAT --to-destination 10.10.10.1:3128
#iptables -t nat -A PREROUTING -i enp1s0.20 -p tcp --dport 443 -j DNAT --to-destination 10.10.10.1:3129

# Redirigir tráfico HTTP (puerto 80) al puerto 3128 del proxy
#iptables -t nat -A PREROUTING -i enp1s0.20 -p tcp --dport 80  ! -s 10.10.10.1 -j DNAT --to-destination 10.10.10.1:3128

# Redirigir tráfico HTTPS (puerto 443) al puerto 3129 del proxy
#iptables -t nat -A PREROUTING -i enp1s0.20 -p tcp --dport 443 ! -s 10.10.10.1 -j DNAT --to-destination 10.10.10.1:3129


# HTTP (80) → Squid (3128)
#iptables -t nat -A PREROUTING -i enp1s0.20 -p tcp --dport 80  -j REDIRECT --to-ports 3128

# HTTPS (443) → Squid (3129)
#iptables -t nat -A PREROUTING -i enp1s0.20 -p tcp --dport 443 -j REDIRECT --to-ports 3129


# --- Permitir reenvío del tráfico hacia el Proxy ---
#iptables -A FORWARD -p tcp -d 10.10.10.1 --dport 3128 -j ACCEPT
#iptables -A FORWARD -p tcp -d 10.10.10.1 --dport 3129 -j ACCEPT

sysctl -p

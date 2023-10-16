#!/bin/bash

# Version of the script
SCRIPT_VERSION="3.0"

# Log file for script output
LOG_FILE="/var/log/pteroshield_script.log"

# Function to add Fail2Ban rules
configure_fail2ban() {
  sudo apt-get update
  sudo apt-get install fail2ban -y

  # Create a custom jail.local file for Fail2Ban
  sudo tee /etc/fail2ban/jail.local > /dev/null <<EOL
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
findtime = 600
bantime = 3600

[custom-service-22]
enabled = true
port = 22
filter = custom-service-22
logpath = /var/log/custom-service-22.log
maxretry = 3
findtime = 600
bantime = 3600

[custom-service-80]
enabled = true
port = 80
filter = custom-service-80
logpath = /var/log/custom-service-80.log
maxretry = 3
findtime = 600
bantime = 3600

[custom-service-8443]
enabled = true
port = 8443
filter = custom-service-8443
logpath = /var/log/custom-service-8443.log
maxretry = 3
findtime = 600
bantime = 3600

[custom-service-9000]
enabled = true
port = 9000
filter = custom-service-9000
logpath = /var/log/custom-service-9000.log
maxretry = 3
findtime = 600
bantime = 3600

[custom-service-9876]
enabled = true
port = 9876
filter = custom-service-9876
logpath = /var/log/custom-service-9876.log
maxretry = 5
findtime = 600
bantime = 3600
EOL

  # Restart Fail2Ban to apply the new configuration
  sudo systemctl restart fail2ban
}

# Update the system
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
sudo apt install nload

# Update the package repository and install Squid
sudo apt-get update
sudo apt-get install squid -y

# Backup the original Squid configuration file
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# Create a new Squid configuration file
sudo tee /etc/squid/squid.conf <<EOL
http_port 3128 transparent
acl localnet src 0.0.0.0/0
acl safe_ports port 80 443
http_access allow localnet safe_ports
http_access deny all
visible_hostname proxy-server

# Cache configurations
cache_dir ufs /var/spool/squid 100 16 256
maximum_object_size 32 MB
refresh_pattern ^ftp:           1440  20% 10080
refresh_pattern ^gopher:        1440  0%  1440
refresh_pattern -i (/cgi-bin/|\?) 0 0% 0
EOL

# Restart Squid to apply the new configuration
sudo systemctl restart squid

# Enable IP forwarding to make the server act as a router
if ! grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Add an iptables rule to redirect HTTP traffic to Squid (port 3128)
if ! sudo iptables -t nat -C PREROUTING -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 3128 2>/dev/null; then
  sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 3128
fi

# Create a swap file
read -p "Do you want to create a swap file? (Y/N): " create_swap
if [[ "$create_swap" == "Y" || "$create_swap" == "y" ]]; then
  read -p "How many GB swap file do you want to allocate? " swap_size_gb

  if [[ "$swap_size_gb" =~ ^[0-9]+$ ]]; then
    swap_size_bytes=$((swap_size_gb * 1024 * 1024 * 1024))

    sudo fallocate -l "$swap_size_bytes" /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    echo "Swap file of $swap_size_gb GB created."
  else
    echo "Invalid input. Please provide a valid number of GB for the swap file."
  fi
else
  echo "No swap file created."
fi

echo "Configuring the firewall..."
# Set the default policies to DROP
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT DROP

# Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow established and related connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP traffic (ping)
sudo iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT

# Rate limit incoming connections to SSH (Port 22)
sudo iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
sudo iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

# Block specified ports
blocked_ports=(465 25 995 143 993 587 5222 5269 5443)
for port in "${blocked_ports[@]}"; do
  sudo iptables -A INPUT -p tcp --dport "$port" -j DROP
  sudo iptables -A INPUT -p udp --dport "$port" -j DROP
done

# Block all outbound traffic, except for established and related connections
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Install iptables-persistent
echo "Installing iptables-persistent..."
sudo apt-get install iptables-persistent -y

# Use tc to limit incoming traffic to 50Mbps for all IP addresses (replace eth0 with your network interface)
sudo tc qdisc add dev eth0 root tbf rate 50mbit burst 10k

# Save and reload the firewall rules
echo "Saving and reloading firewall rules..."
sudo netfilter-persistent save
sudo netfilter-persistent reload

# End of Firewall Configuration
echo "Firewall configuration completed."

# Set resource limits for Docker containers
echo "Setting resource limits for Docker containers..."
storage_limit="100G"
bandwidth_limit="100mbit"

for CONTAINER_UUID in $(docker ps -q); do
  docker update --storage-opt size="$storage_limit" $CONTAINER_UUID
  docker exec $CONTAINER_UUID tc qdisc add dev eth0 root tbf rate "$bandwidth_limit" burst 10kbit latency 50ms
done

# Configure Pterodactyl Wings game ports
read -p "What ports are you going going to allocate for Pterodactyl Wings game ports (e.g., 5000-5999 recommended)? " wing_ports

if [[ "$wing_ports" =~ ^[0-9]+-[0-9]+$ ]]; then
  IFS='-' read -ra port_range <<< "$wing_ports"
  start_port="${port_range[0]}"
  end_port="${port_range[1]}"

  sudo ufw allow "$start_port":"$end_port/tcp"
  sudo ufw allow "$start_port":"$end_port/udp"

  echo "Ports $start_port to $end_port for Pterodactyl Wings have been allowed (TCP and UDP)."
else
  echo "Invalid input. Please provide a valid range in the format of 'start-end' (e.g., 5000-5999)."
fi

# Configure Fail2Ban
configure_fail2ban

# Install Pterodactyl Wings
read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " INSTALL_WINGS
if [ "$INSTALL_WINGS" == "Y" ] || [ "$INSTALL_WINGS" == "y" ]; then
  echo "Installing Pterodactyl Wings..." | tee -a "$LOG_FILE"
  bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LOG_FILE"
  echo "Pterodactyl Wings installation completed." | tee -a "$LOG_FILE"
else
  echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LOG_FILE"
fi

echo "Script Version: $SCRIPT_VERSION installed!" | tee -a "$LOG_FILE"
echo "PteroShield execution completed." | tee -a "$LOG_FILE"

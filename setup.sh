#!/bin/bash

SCRIPT_VERSION="dev_ver_not_for_use_atm"

LOG_FILE="/var/log/myridax_script.log"

configure_fail2ban() {
  sudo apt-get update
  sudo apt-get install fail2ban -y

  sudo tee /etc/fail2ban/jail.local > /dev/null <<EOL
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 600
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 6
findtime = 600
bantime = 3600
EOL

  # Restart Fail2Ban to apply the new configuration
  sudo service fail2ban restart
}
sudo apt update
sudo apt upgrade 
sudo apt autoremove 
# This example rate limits incoming traffic to 50 Mbps on the eth0 interface
sudo iptables -A INPUT -i eth0 -p tcp --dport 80 -m conntrack --ctstate NEW -m limit --limit 50/s -j ACCEPT
sudo iptables -A INPUT -i eth0 -p tcp --dport 80 -m conntrack --ctstate NEW -j DROP
blocked_ports=(465 25 26 995 143 22 110 993 587 5222 5269 5443)
for port in "${blocked_ports[@]}"; do
  sudo iptables -I FORWARD 1 -p tcp -m tcp --dport "$port" -j DROP
  sudo iptables -I FORWARD 1 -p udp -m udp --dport "$port" -j DROP
done
DIRECTORY="/var/lib/pterodactyl/volumes/*"
for CONTAINER_UUID in $(docker ps -q); do
  docker exec $CONTAINER_UUID tc qdisc add dev eth0 root tbf rate 50mbit burst 10kbit latency 50ms
  docker update --storage-opt size=40G $CONTAINER_UUID
done
sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m limit --limit 10/s -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -j DROP
sudo ufw enable 
sudo ufw allow 8443/tcp
sudo ufw allow 5000:5999/tcp
sudo ufw allow 5000:5999/udp
sudo apt-get install iptables-persistent -y
sudo netfilter-persistent save
sudo netfilter-persistent reload

configure_fail2ban

read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " INSTALL_WINGS
if [ "$INSTALL_WINGS" == "Y" ] || [ "$INSTALL_WINGS" == "y" ]; then
  # Run the Pterodactyl Wings installation script with logging
  echo "Installing Pterodactyl Wings..." | tee -a "$LOG_FILE"
  bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LOG_FILE"
  echo "Pterodactyl Wings installation completed." | tee -a "$LOG_FILE"
else
  echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LOG_FILE"
fi

echo "Script Version: $SCRIPT_VERSION installed!" | tee -a "$LOG_FILE"

echo "PteroShield Test Script execution completed." | tee -a "$LOG_FILE"

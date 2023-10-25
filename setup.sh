#!/bin/bash

DISCORD_WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL"
HOST_NAME="PteroShield"
CONFIG_FILE="/root/pteroshield/config.yml"

configure_discord_webhook() {
  read -p "Enter your Discord webhook URL: " DISCORD_WEBHOOK_URL
  read -p "Enter your host name: " HOST_NAME
  echo "DISCORD_WEBHOOK_URL=\"$DISCORD_WEBHOOK_URL\"" >> "$CONFIG_FILE"
  echo "HOST_NAME=\"$HOST_NAME\"" >> "$CONFIG_FILE"
  echo "Discord webhook and host name configured."
}

create_default_config() {
  mkdir -p /root/pteroshield

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating a default configuration file..."
    cat <<EOF >"$CONFIG_FILE"
DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL"
HOST_NAME="$HOST_NAME"
SL=100G
BL=100mbit
NL=100mbit
NWDL=100mbit
WP="5000-6000"
IW="N"
CS="N"
SSG=2
BP="Y"
EOF
    echo "Default configuration file created at $CONFIG_FILE"
  fi
}

load_configuration() {
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
}

setup_log_directory() {
  LD="/root/pteroshield/log"
  LF="$LD/pteroshield_script.log"
  mkdir -p "$LD"
}

create_swap_file() {
  load_configuration
  if [ "$CS" == "Y" ] || [ "$CS" == "y" ]; then
    read -p "How many GB swap file do you want to allocate? " SSG
    if [[ "$SSG" =~ ^[0-9]+$ ]]; then
      SSGB=$((SSG * 1024 * 1024 * 1024))
      sudo fallocate -l "$SSGB" /swapfile
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile
      sudo swapon /swapfile
      echo "Swap file of $SSG GB created."
    else
      echo "Invalid input. Please provide a valid number of GB for the swap file."
    fi
  else
    echo "No swap file created."
  fi
}

block_ports_and_install_iptables() {
  load_configuration

  if [ "$BP" == "Y" ] || [ "$BP" == "y" ]; then
    BLOCKED_PORTS=(465 25 995 143 993 587 5222 5269 5443)
    for P in "${BLOCKED_PORTS[@]}"; do
      sudo iptables -A INPUT -p tcp --dport "$P" -j DROP
      sudo iptables -A INPUT -p udp --dport "$P" -j DROP
    done
    echo "Default policies to DROP set for specified ports."
  fi

  echo "Installing iptables-persistent..."
  sudo apt-get install iptables-persistent -y
  echo "Saving blocked ports..."
  sudo netfilter-persistent save
  sudo netfilter-persistent reload
}

update_docker_settings() {
  load_configuration
  SL="$SL"
  BL="$BL"
  for CU in $(docker ps -q); do
    docker update --storage-opt size="$SL" $CU
    docker exec $CU tc qdisc add dev eth0 root tbf rate "$BL" burst 10kbit latency 50ms
  done
}

allow_pterodactyl_wings() {
  load_configuration
  read -p "What ports are you going to allocate for Pterodactyl Wings game ports (e.g., 5000-6000)? " WP

  if [[ "$WP" =~ ^[0-9]+-[0-9]+$ ]]; then
    IFS='-' read -ra PR <<< "$WP"
    SP="${PR[0]}"
    EP="${PR[1]}"
    sudo ufw allow "$SP":"$EP/tcp"
    sudo ufw allow "$SP":"$EP/udp"
    echo "Ports $SP to $EP for Pterodactyl Wings have been allowed (TCP and UDP)."
  else
    echo "Invalid input. Please provide a valid range in the format of 'start-end' (e.g., 5000-5999)."
  fi
}

install_pterodactyl_wings() {
  load_configuration
  read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " IW

  if [ "$IW" == "Y" ] || [ "$IW" == "y" ]; then
    echo "Installing Pterodactyl Wings..." | tee -a "$LF"
    bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LF"
    echo "Pterodactyl Wings installation completed." | tee -a "$LF"
  else
    echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LF"
  fi
}

allow_pterodactyl_wings() {
  load_configuration
  read -p "What ports are you going to allocate for Pterodactyl Wings game ports (e.g., 5000-6000)? " WP

  if [[ "$WP" =~ ^[0-9]+-[0-9]+$ ]]; then
    IFS='-' read -ra PR <<< "$WP"
    SP="${PR[0]}"
    EP="${PR[1]}"
    sudo ufw allow "$SP":"$EP/tcp"
    sudo ufw allow "$SP":"$EP/udp"
    echo "Ports $SP to $EP for Pterodactyl Wings have been allowed (TCP and UDP)."
  else
    echo "Invalid input. Please provide a valid range in the format of 'start-end' (e.g., 5000-5999)."
  fi
}

monitor_container_cpu_usage() {
  load_configuration
  while true; do
    stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}")

    while read -r line; do
      container_name=$(echo "$line" | awk '{print $1}')
      cpu_usage=$(echo "$line" | awk -F'%' '{print $1}' | awk '{print $NF}')

      if (( $(echo "$cpu_usage > 100" | bc -l) )); then
        echo "High CPU usage detected in container: $container_name"
        message=":warning: High CPU usage detected in container *$container_name* on *$HOST_NAME*. CPU Usage: *$cpu_usage%*"
        curl -H "Content-Type: application/json" -d "{\"content\":\"$message\"}" "$DISCORD_WEBHOOK_URL"
      fi
    done <<< "$(echo "$stats" | tail -n +2)"

    sleep 60
  done
}

configure_discord_webhook
create_default_config
setup_log_directory
create_swap_file
block_ports_and_install_iptables
update_docker_settings
allow_pterodactyl_wings
install_pterodactyl_wings

monitor_container_cpu_usage &

install_pterodactyl_wings() {
  load_configuration
  read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " IW

  if [ "$IW" == "Y" ] || [ "$IW" == "y" ]; then
    echo "Installing Pterodactyl Wings..." | tee -a "$LOG_FILE"
    bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LOG_FILE"
    echo "Pterodactyl Wings installation completed." | tee -a "$LOG_FILE"
  else
    echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LOG_FILE"
  fi
}

# Display completion messages
echo "Script Version: $SCRIPT_VERSION installed!" | tee -a "$LOG_FILE"
echo "PteroShield execution completed." | tee -a "$LOG_FILE"

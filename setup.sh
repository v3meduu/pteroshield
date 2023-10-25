#!/bin/bash

CONFIG_FILE="/root/pteroshield/config.yml"

prompt_for_configuration() {
  read -p "Enter your Discord webhook URL: " DISCORD_WEBHOOK_URL
  read -p "Enter your host name: " HOST_NAME
  read -p "Enter the storage limit in GB (e.g., 100G) to prevent diskfills: " STORAGE_LIMIT
  read -p "Enter the network limit for each server in mbps (e.g., 100mbit): " NETWORK_LIMIT
  read -p "Do you want to allocate a swap file? (Y/N): " SWAP_FILE
  read -p "Do you want to block default ports? (Y/N): " BLOCK_PORTS
  if [ "$BLOCK_PORTS" == "Y" ] || [ "$BLOCK_PORTS" == "y" ]; then
    read -p "Enter the ports you want to block (e.g., 465 25 995): " -a BLOCKED_PORTS
  fi
  read -p "What ports are you going to allocate for Pterodactyl Wings game ports (e.g., 5000-6000)? " PTERODACTYL_WINGS_PORTS
  read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " PTERODACTYL_WINGS_INSTALL

  echo "DISCORD_WEBHOOK_URL=\"$DISCORD_WEBHOOK_URL\"" >> "$CONFIG_FILE"
  echo "HOST_NAME=\"$HOST_NAME\"" >> "$CONFIG_FILE"
  echo "STORAGE_LIMIT=\"$STORAGE_LIMIT\"" >> "$CONFIG_FILE"
  echo "NETWORK_LIMIT=\"$NETWORK_LIMIT\"" >> "$CONFIG_FILE"
  echo "SWAP_FILE=\"$SWAP_FILE\"" >> "$CONFIG_FILE"
  if [ "$BLOCK_PORTS" == "Y" ] || [ "$BLOCK_PORTS" == "y" ]; then
    echo "BLOCK_PORTS=\"$BLOCK_PORTS\"" >> "$CONFIG_FILE"
    for P in "${BLOCKED_PORTS[@]}"; do
      echo "BLOCKED_PORTS+=($P)" >> "$CONFIG_FILE"
    done
  fi
  echo "PTERODACTYL_WINGS_PORTS=\"$PTERODACTYL_WINGS_PORTS\"" >> "$CONFIG_FILE"
  echo "PTERODACTYL_WINGS_INSTALL=\"$PTERODACTYL_WINGS_INSTALL\"" >> "$CONFIG_FILE"
  echo "Configuration completed and saved to $CONFIG_FILE."
}

create_default_config() {
  mkdir -p /root/pteroshield

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating a default configuration file..."
    cat <<EOF >"$CONFIG_FILE"
DISCORD_WEBHOOK_URL=""
HOST_NAME=""
STORAGE_LIMIT=""
NETWORK_LIMIT=""
SWAP_FILE=""
BLOCK_PORTS=""
BLOCKED_PORTS=()
PTERODACTYL_WINGS_PORTS=""
PTERODACTYL_WINGS_INSTALL=""
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
  if [ "$SWAP_FILE" == "Y" ] || [ "$SWAP_FILE" == "y" ]; then
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

  if [ "$BLOCK_PORTS" == "Y" ] || [ "$BLOCK_PORTS" == "y" ]; then
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
  SL="$STORAGE_LIMIT"
  BL="$NETWORK_LIMIT"
  for CU in $(docker ps -q); do
    docker update --storage-opt size="$SL" $CU
    docker exec $CU tc qdisc add dev eth0 root tbf rate "$BL" burst 10kbit latency 50ms
  done
}

allow_pterodactyl_wings() {
  load_configuration
  if [ -n "$PTERODACTYL_WINGS_PORTS" ]; then
    if [[ "$PTERODACTYL_WINGS_PORTS" =~ ^[0-9]+-[0-9]+$ ]]; then
      IFS='-' read -ra PR <<< "$PTERODACTYL_WINGS_PORTS"
      SP="${PR[0]}"
      EP="${PR[1]}"
      sudo ufw allow "$SP":"$EP/tcp"
      sudo ufw allow "$SP":"$EP/udp"
      echo "Ports $SP to $EP for Pterodactyl Wings have been allowed (TCP and UDP)."
    else
      echo "Invalid input for Pterodactyl Wings ports. Please provide a valid range in the format of 'start-end' (e.g., 5000-5999)."
    fi
  else {
    echo "No Pterodactyl Wings ports specified."
  }
}

install_pterodactyl_wings() {
  load_configuration
  if [ "$PTERODACTYL_WINGS_INSTALL" == "Y" ] || [ "$PTERODACTYL_WINGS_INSTALL" == "y" ]; then
    echo "Installing Pterodactyl Wings..." | tee -a "$LF"
    bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LF"
    echo "Pterodactyl Wings installation completed." | tee -a "$LF"
  else {
    echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LF"
  }
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

# Main script
prompt_for_configuration
create_default_config
setup_log_directory
create_swap_file
block_ports_and_install_iptables
update_docker_settings
allow_pterodactyl_wings
install_pterodactyl_wings

monitor_container_cpu_usage &

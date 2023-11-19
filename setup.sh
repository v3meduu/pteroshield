#!/bin/bash

CONFIG_FILE="/root/pulsar_security/config.yml"
LOG_DIRECTORY="/root/pulsar_security/log"
LOG_FILE="$LOG_DIRECTORY/pulsar_security_script.log"

# Function to prompt for configuration
prompt_for_configuration() {
  read -p "Enter your Discord webhook URL: " DISCORD_WEBHOOK_URL
  read -p "Enter your host name: " HOST_NAME
  read -p "Enter the storage limit in GB (e.g., 100G) to prevent disk fills: " STORAGE_LIMIT
  read -p "Enter the network limit for each server in mbps (e.g., 100mbit): " NETWORK_LIMIT
  read -p "Do you want to allocate a swap file? (Y/N): " SWAP_FILE
  read -p "Do you want to block default ports? (Y/N): " BLOCK_PORTS
  if [[ "$BLOCK_PORTS" =~ ^[Yy]$ ]]; then
    BLOCKED_PORTS=("22" "23" "3389")  # You can customize this list
  fi
  read -p "What ports are you going to allocate for Pterodactyl Wings game ports (e.g., 5000-6000)? " PTERODACTYL_WINGS_PORTS
  read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " PTERODACTYL_WINGS_INSTALL

  echo "DISCORD_WEBHOOK_URL=\"$DISCORD_WEBHOOK_URL\"" > "$CONFIG_FILE"
  echo "HOST_NAME=\"$HOST_NAME\"" >> "$CONFIG_FILE"
  echo "STORAGE_LIMIT=\"$STORAGE_LIMIT\"" >> "$CONFIG_FILE"
  echo "NETWORK_LIMIT=\"$NETWORK_LIMIT\"" >> "$CONFIG_FILE"
  echo "SWAP_FILE=\"$SWAP_FILE\"" >> "$CONFIG_FILE"
  if [[ "$BLOCK_PORTS" =~ ^[Yy]$ ]]; then
    echo "BLOCK_PORTS=\"$BLOCK_PORTS\"" >> "$CONFIG_FILE"
    for P in "${BLOCKED_PORTS[@]}"; do
      echo "BLOCKED_PORTS+=($P)" >> "$CONFIG_FILE"
    done
  fi
  echo "PTERODACTYL_WINGS_PORTS=\"$PTERODACTYL_WINGS_PORTS\"" >> "$CONFIG_FILE"
  echo "PTERODACTYL_WINGS_INSTALL=\"$PTERODACTYL_WINGS_INSTALL\"" >> "$CONFIG_FILE"
  echo "Configuration completed and saved to $CONFIG_FILE."
}

# Function to create a default configuration
create_default_config() {
  mkdir -p /root/pulsar_security

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

# Function to load configuration from file
load_configuration() {
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
}

# Function to set up log directory
setup_log_directory() {
  mkdir -p "$LOG_DIRECTORY"
}

# Function to create a swap file based on user input
create_swap_file() {
  load_configuration
  if [[ "$SWAP_FILE" =~ ^[Yy]$ ]]; then
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

# Function to block default ports and install iptables
block_default_ports_and_install_iptables() {
  BLOCKED_PORTS=("22" "23" "3389")  # You can customize this list
  echo "Blocking default ports for SSH, Telnet, and RDP..."
  for P in "${BLOCKED_PORTS[@]}"; do
    sudo iptables -A INPUT -p tcp --dport "$P" -j DROP
    sudo iptables -A INPUT -p udp --dport "$P" -j DROP
  done
  echo "Default ports blocked for SSH, Telnet, and RDP."
}

# Function to update Docker settings
update_docker_settings() {
  load_configuration
  SL="$STORAGE_LIMIT"
  BL="$NETWORK_LIMIT"
  for CU in $(docker ps -q); do
    docker update --storage-opt size="$SL" $CU
    docker exec $CU tc qdisc add dev eth0 root tbf rate "$BL" burst 10kbit latency 50ms
  done
}

# Function to allow Pterodactyl Wings ports
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
  else
    echo "No Pterodactyl Wings ports specified."
  fi
}

# Function to install Pterodactyl Wings
install_pterodactyl_wings() {
  load_configuration
  if [[ "$PTERODACTYL_WINGS_INSTALL" =~ ^[Yy]$ ]]; then
    echo "Installing Pterodactyl Wings..." | tee -a "$LOG_FILE"
    bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LOG_FILE"
    echo "Pterodactyl Wings installation completed." | tee -a "$LOG_FILE"
  else
    echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LOG_FILE"
  fi
}

# Function to monitor container CPU usage continuously
monitor_container_cpu_usage() {
  load_configuration
  while true; do
    stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}")

    while read -r line; do
      container_name=$(echo "$line" | awk '{print $1}')
      cpu_usage=$(echo "$line" | awk '{gsub(/%/, "", $NF); print $NF}')

      if (( $(echo "$cpu_usage > 100" | bc) )); then
        echo "High CPU usage detected in container: $container_name"
        message=":warning: High CPU usage detected in container *$container_name* on *$HOST_NAME*. CPU Usage: *$cpu_usage%*"
        curl -H "Content-Type: application/json" -d "{\"content\":\"$message\"}" "$DISCORD_WEBHOOK_URL"
      fi
    done <<< "$(echo "$stats" | tail -n +2)"

    sleep 60
  done
}

# Main script

# Set up configurations
prompt_for_configuration
create_default_config
setup_log_directory
create_swap_file
block_default_ports_and_install_iptables
update_docker_settings
allow_pterodactyl_wings
install_pterodactyl_wings

# Continuous CPU monitoring in the background
monitor_container_cpu_usage &

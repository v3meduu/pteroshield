#!/bin/bash

# Script version
SCRIPT_VERSION="8.0"

# Configuration file
CONFIG_FILE="/root/pteroshield/config.yml"

# Function to create a default configuration file if it doesn't exist
create_config_file() {
  mkdir -p /root/pteroshield
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating a default configuration file..."
    cat <<EOF >"$CONFIG_FILE"
# PteroShield Configuration
storage_limit: 100G
bandwidth_limit: 100mbit
network_docker_limit: 100mbit
network_limit: 100mbit
wing_ports: "5000-6000"
install_wings: "N"
create_swap: "N"
swap_size_gb: 2
block_ports: "Y"
EOF
    echo "Default configuration file created at $CONFIG_FILE"
  fi
}

# Function to load configuration from the config file
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
  fi
}

# Function to create a log directory and set the log file
create_log_file() {
  LOG_DIR="/root/pteroshield/log"
  LOG_FILE="$LOG_DIR/pteroshield_script.log"
  
  mkdir -p "$LOG_DIR"
}

# Function to create a swap file
create_swap_file() {
  load_config
  if [ "$create_swap" == "Y" ] || [ "$create_swap" == "y" ]; then
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
}

# Function to configure the firewall and block specified ports
configure_firewall() {
  load_config
  if [ "$block_ports" == "Y" ] || [ "$block_ports" == "y" ]; then
    blocked_ports=(465 25 995 143 993 587 5222 5269 5443)
    for port in "${blocked_ports[@]}"; do
      sudo iptables -A INPUT -p tcp --dport "$port" -j DROP
      sudo iptables -A INPUT -p udp --dport "$port" -j DROP
    done

    echo "Default policies to DROP set for specified ports."
  fi

  # Install iptables-persistent
  echo "Installing iptables-persistent..."
  sudo apt-get install iptables-persistent -y

  # Save and reload the firewall rules
  echo "Saving blocked ports..."
  sudo netfilter-persistent save
  sudo netfilter-persistent reload
}

# Function to set resource limits for Docker containers
set_docker_resource_limits() {
  load_config
  storage_limit="$storage_limit"
  bandwidth_limit="$bandwidth_limit"
  
  for CONTAINER_UUID in $(docker ps -q); do
    docker update --storage-opt size="$storage_limit" $CONTAINER_UUID
    docker exec $CONTAINER_UUID tc qdisc add dev eth0 root tbf rate "$bandwidth_limit" burst 10kbit latency 50ms
  done
}

# Function to configure Pterodactyl Wings game ports
configure_pterodactyl_ports() {
  load_config
  read -p "What ports are you going to allocate for Pterodactyl Wings game ports (e.g., 5000-6000)? " wing_ports

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
}

# Function to install Pterodactyl Wings
install_pterodactyl_wings() {
  load_config
  read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " INSTALL_WINGS
  if [ "$INSTALL_WINGS" == "Y" ] || [ "$INSTALL_WINGS" == "y" ]; then
    echo "Installing Pterodactyl Wings..." | tee -a "$LOG_FILE"
    bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LOG_FILE"
    echo "Pterodactyl Wings installation completed." | tee -a "$LOG_FILE"
  else
    echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LOG_FILE"
  fi
}

# Main script execution
create_config_file
create_log_file

create_swap_file
configure_firewall
set_docker_resource_limits
configure_pterodactyl_ports
install_pterodactyl_wings

echo "Script Version: $SCRIPT_VERSION installed!" | tee -a "$LOG_FILE"
echo "PteroShield execution completed." | tee -a "$LOG_FILE"

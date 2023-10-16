#!/bin/bash
SV="8.0"
CF="/root/pteroshield/config.yml"

f1() {
  mkdir -p /root/pteroshield
  [ ! -f "$CF" ] && { echo "Creating a default configuration file..."; cat <<EOF >"$CF";SL=100G;BL=100mbit;NL=100mbit;NWDL=100mbit;WP="5000-6000";IW="N";CS="N";SSG=2;BP="Y";EOF; echo "Default configuration file created at $CF"; }
}

f2() {
  [ -f "$CF" ] && . "$CF"
}

f3() {
  LD="/root/pteroshield/log"
  LF="$LD/pteroshield_script.log"
  mkdir -p "$LD"
}

f4() {
  f2
  [ "$CS" == "Y" ] || [ "$CS" == "y" ] && { read -p "How many GB swap file do you want to allocate? " SSG; [[ "$SSG" =~ ^[0-9]+$ ]] && { SSGB=$((SSG*1024*1024*1024)); sudo fallocate -l "$SSGB" /swapfile; sudo chmod 600 /swapfile; sudo mkswap /swapfile; sudo swapon /swapfile; echo "Swap file of $SSG GB created."; } || echo "Invalid input. Please provide a valid number of GB for the swap file."; } || echo "No swap file created."
}

f5() {
  f2
  [ "$BP" == "Y" ] || [ "$BP" == "y" ] && { BP=(465 25 995 143 993 587 5222 5269 5443); for P in "${BP[@]}"; do sudo iptables -A INPUT -p tcp --dport "$P" -j DROP; sudo iptables -A INPUT -p udp --dport "$P" -j DROP; done; echo "Default policies to DROP set for specified ports."; }
  echo "Installing iptables-persistent..."; sudo apt-get install iptables-persistent -y
  echo "Saving blocked ports..."; sudo netfilter-persistent save; sudo netfilter-persistent reload
}

f6() {
  f2
  SL="$SL"
  BL="$BL"
  for CU in $(docker ps -q); do docker update --storage-opt size="$SL" $CU; docker exec $CU tc qdisc add dev eth0 root tbf rate "$BL" burst 10kbit latency 50ms; done
}

f7() {
  f2
  read -p "What ports are you going to allocate for Pterodactyl Wings game ports (e.g., 5000-6000)? " WP
  [[ "$WP" =~ ^[0-9]+-[0-9]+$ ]] && { IFS='-' read -ra PR <<< "$WP"; SP="${PR[0]}"; EP="${PR[1]}"; sudo ufw allow "$SP":"$EP/tcp"; sudo ufw allow "$SP":"$EP/udp"; echo "Ports $SP to $EP for Pterodactyl Wings have been allowed (TCP and UDP)."; } || echo "Invalid input. Please provide a valid range in the format of 'start-end' (e.g., 5000-5999)."
}

f8() {
  f2
  read -p "Do you want to run the Pterodactyl Wings installation now? (Y/N): " IW
  [ "$IW" == "Y" ] || [ "$IW" == "y" ] && { echo "Installing Pterodactyl Wings..." | tee -a "$LF"; bash <(curl -s https://pterodactyl-installer.se/) 2>&1 | tee -a "$LF"; echo "Pterodactyl Wings installation completed." | tee -a "$LF"; } || echo "Pterodactyl Wings installation skipped. You can run it manually when ready." | tee -a "$LF"
}

f1
f3
f4
f5
f6
f7
f8
echo "Script Version: $SV installed!" | tee -a "$LF"
echo "PteroShield execution completed." | tee -a "$LF"

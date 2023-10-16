# PteroShield - Protect your Pterodactyl Wings.

```
curl -o pteroshield_setup.sh https://raw.githubusercontent.com/v3meduu/pteroshield/main/setup.sh
chmod +x pteroshield_setup.sh
./pteroshield_setup.sh
```

Are you operating a no-cost Minecraft hosting service? Ensure the security of your servers with PteroShield, the protective script for Pterodactyl Wing. PteroShield shields your servers from potential risks such as disk overload and defends against DDoS attacks initiated by your users. It comes equipped with multiple layers of security to guarantee the safety of your servers.

## This script safeguards your host from:

- **DDoS attacks**: (including nodes used for DDoSing).
- **Disk filling**: (limited to 100GB).
- **Bitcoin Mining Prevention**: This script includes measures to prevent Bitcoin mining. You can manually configure the CPU trigger for suspension in the `/root/pteroshield/config.yml` file.

## Features

- **Configuration**: All settings can be conveniently configured in the `/root/pteroshield/config.yml` file.
- **Discord Alert**: Discord webhook functionality for attacks can be enabled in the configuration file, and you can customize the webhook embed message to suit your needs.
- **Auto Update**: PteroShield automatically updates itself daily to safeguard all hosts from vulnerabilities, exploits, and provide additional layers of security.
 - **Pterodactyl Wings Installation**: After completing the script installation, [PteroShield will prompt you to install Pterodactyl wings](https://github.com/pterodactyl-installer/pterodactyl-installer).

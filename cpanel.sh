#!/bin/bash
set -e

# Setup Colors
RED='\033[0;31m'
NC='\033[0m'
WHITE='\033[1;37m'

clear

# Animated Red TheRynzo Banner
echo -e "${RED}"
cat << "EOF" | while read -r line; do echo "$line"; sleep 0.05; done
 _____ _       ___
|_   _| |_ ___| _ \_  _ _ _  ____ ___
  | | | ' \ -_)   / || | ' \|_  // _ \
  |_| |_||_\___|_|_\_, |_||_|/__/\___/
                   |__/
EOF
echo -e "${NC}"

# Animated Subtitle
SUBTITLE="cPanel Auto-Installer"
echo -e "${RED}"
for (( i=0; i<${#SUBTITLE}; i++ )); do
    echo -n "${SUBTITLE:$i:1}"
    sleep 0.03
done
echo -e "${NC}\n"

# 1. Root Check
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}✘ Error: Please run this installer as root (sudo).${NC}"
    exit 1
fi

# 2. OS Compatibility Verification (Ubuntu 20.04 / 22.04 LTS per cpanel.net)
echo -e "${RED}➤${NC} ${WHITE}Checking system compatibility with cpanel.net requirements...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        echo -e "${RED}⚠ Warning: Official cPanel installation on Ubuntu requires Ubuntu 20.04 or 22.04 LTS.${NC}"
        echo -e "${RED}Detected OS: $PRETTY_NAME${NC}"
        read -p "Do you want to continue anyway? (y/n): " OS_CONFIRM
        if [[ "$OS_CONFIRM" != "y" && "$OS_CONFIRM" != "Y" ]]; then
            echo -e "${RED}Installation cancelled.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}✔ Compatible OS Detected:${NC} ${WHITE}$PRETTY_NAME${NC}"
    fi
fi

echo ""
echo -e "${RED}====================================================${NC}"
echo -e "${WHITE}  STEP-BY-STEP CONFIGURATION${NC}"
echo -e "${RED}====================================================${NC}"

# Step 1: Domain / Hostname Input
while true; do
    echo -ne "${RED}➤ Step 1: Enter your FQDN Domain/Hostname (e.g., cpanel.yourdomain.com): ${NC}"
    read DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Domain cannot be empty.${NC}"
    else
        break
    fi
done

# Step 2: Email Input
while true; do
    echo -ne "${RED}➤ Step 2: Enter Admin Contact Email: ${NC}"
    read EMAIL
    if [ -z "$EMAIL" ]; then
        echo -e "${RED}Email cannot be empty.${NC}"
    else
        break
    fi
done

# Step 3: Set Password
echo -ne "${RED}➤ Step 3: Set Server Root Password (Press Enter to keep current password): ${NC}"
read -s PASSWORD
echo ""
if [ -n "$PASSWORD" ]; then
    echo "root:$PASSWORD" | chpasswd
    echo -e "${RED}✔ Root password updated successfully.${NC}"
fi

echo -e "\n${RED}====================================================${NC}"
echo -e "${WHITE}  STARTING CPANEL INSTALLATION${NC}"
echo -e "${RED}====================================================${NC}\n"

# Set Hostname
echo -e "${RED}➤ Setting system hostname to $DOMAIN...${NC}"
hostnamectl set-hostname "$DOMAIN" || hostname "$DOMAIN"

# Update Packages
echo -e "${RED}➤ Updating package repository...${NC}"
apt-get update -y && apt-get install -y curl wget ufw lsof

# Open Port 9000 & cPanel Ports
echo -e "${RED}➤ Opening Port 9000 & standard cPanel/WHM ports (2082, 2083, 2086, 2087)...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 9000/tcp comment 'Custom Port 9000' >/dev/null 2>&1 || true
    ufw allow 2082/tcp >/dev/null 2>&1 || true
    ufw allow 2083/tcp >/dev/null 2>&1 || true
    ufw allow 2086/tcp >/dev/null 2>&1 || true
    ufw allow 2087/tcp >/dev/null 2>&1 || true
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
fi

if command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport 9000 -j ACCEPT >/dev/null 2>&1 || true
    iptables -I INPUT -p tcp --dport 2087 -j ACCEPT >/dev/null 2>&1 || true
    iptables -I INPUT -p tcp --dport 2083 -j ACCEPT >/dev/null 2>&1 || true
fi

# Download and Execute Official cPanel Installer from cPanel.net
echo -e "${RED}➤ Downloading official installer from cpanel.net...${NC}"
cd /home
curl -o latest -L https://secured.cpanel.net/latest
sh latest

PUBLIC_IP=$(curl -s -m 5 ifconfig.me || hostname -I | awk '{print $1}')

echo -e "\n${RED}====================================================${NC}"
echo -e "${WHITE}  CPANEL INSTALLATION COMPLETE${NC}"
echo -e "${RED}====================================================${NC}"
echo -e "${RED}➤ WHM Admin URL   :${NC} ${WHITE}https://$PUBLIC_IP:2087${NC} or ${WHITE}https://$DOMAIN:2087${NC}"
echo -e "${RED}➤ cPanel User URL  :${NC} ${WHITE}https://$PUBLIC_IP:2083${NC} or ${WHITE}https://$DOMAIN:2083${NC}"
echo -e "${RED}➤ Port 9000 Status :${NC} ${WHITE}OPENED${NC}"
echo -e "${RED}➤ Admin Email     :${NC} ${WHITE}$EMAIL${NC}"
echo -e "${RED}➤ Hostname        :${NC} ${WHITE}$DOMAIN${NC}"
echo -e "${RED}====================================================${NC}\n"

#!/bin/bash
set -e

# Setup Colors
RED='\033[0;31m'
NC='\033[0m'
WHITE='\033[1;37m'

clear

# Animated Red TheRynzo Banner
echo -e "${RED}"
cat << "EOF" | while read -r line; do echo "$line"; sleep 0.03; done
 _____ _       ___
|_   _| |_ ___| _ \_  _ _ _  ____ ___
  | | | ' \ -_)   / || | ' \|_  // _ \
  |_| |_||_\___|_|_\_, |_||_|/__/\___/
                   |__/
EOF
echo -e "${NC}"

# Animated Subtitle
SUBTITLE="cPanel Auto-Installer (Default Ports & DNS Fixed)"
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

# 2. Forceful DNS Fix (Removes broken symlinks & rebuilds /etc/resolv.conf)
echo -e "${RED}➤ Repairing system DNS resolution (8.8.8.8 & 1.1.1.1)...${NC}"
chattr -i /etc/resolv.conf 2>/dev/null || true
rm -f /etc/resolv.conf
cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF

if command -v systemctl >/dev/null 2>&1; then
    sed -i 's/#DNS=/DNS=8.8.8.8 1.1.1.1/g' /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved >/dev/null 2>&1 || true
fi

# 3. OS Compatibility Verification
echo -e "${RED}➤ Checking OS compatibility...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        echo -e "${RED}⚠ Warning: Official cPanel installation requires Ubuntu 20.04 or 22.04 LTS.${NC}"
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
    echo -ne "${RED}➤ Step 1: Enter your FQDN Domain/Hostname (e.g., cpanel.nexiohost.net): ${NC}"
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

# Update Packages & Install Core Tools
echo -e "${RED}➤ Updating package repository...${NC}"
apt-get update -y && apt-get install -y curl wget ufw lsof ca-certificates

# Open Standard cPanel/WHM Default Ports
echo -e "${RED}➤ Opening default cPanel/WHM ports (2082, 2083, 2086, 2087, 80, 443)...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 2082/tcp comment 'cPanel HTTP' >/dev/null 2>&1 || true
    ufw allow 2083/tcp comment 'cPanel HTTPS' >/dev/null 2>&1 || true
    ufw allow 2086/tcp comment 'WHM HTTP' >/dev/null 2>&1 || true
    ufw allow 2087/tcp comment 'WHM HTTPS' >/dev/null 2>&1 || true
    ufw allow 2095/tcp comment 'Webmail HTTP' >/dev/null 2>&1 || true
    ufw allow 2096/tcp comment 'Webmail HTTPS' >/dev/null 2>&1 || true
    ufw allow 80/tcp comment 'HTTP' >/dev/null 2>&1 || true
    ufw allow 443/tcp comment 'HTTPS' >/dev/null 2>&1 || true
fi

if command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport 2087 -j ACCEPT >/dev/null 2>&1 || true
    iptables -I INPUT -p tcp --dport 2083 -j ACCEPT >/dev/null 2>&1 || true
fi

# Download Installer using Official cPanel URLs
echo -e "${RED}➤ Downloading official cPanel installer from cPanel mirrors...${NC}"
cd /home
rm -f latest

if curl -o latest -L https://securedownloads.cpanel.net/latest; then
    echo -e "${RED}✔ Successfully downloaded installer from primary cPanel server.${NC}"
else
    echo -e "${RED}⚠ Primary mirror failed, trying secondary fallback mirror...${NC}"
    curl -o latest -L http://httpupdate.cpanel.net/latest
fi

# Execute Installer
echo -e "${RED}➤ Launching official cPanel installation process (takes 15-30 minutes)...${NC}"
sh latest

PUBLIC_IP=$(curl -s -m 5 ifconfig.me || hostname -I | awk '{print $1}')

echo -e "\n${RED}====================================================${NC}"
echo -e "${WHITE}  CPANEL INSTALLATION COMPLETE${NC}"
echo -e "${RED}====================================================${NC}"
echo -e "${RED}➤ WHM Admin (Default SSL)  :${NC} ${WHITE}https://$PUBLIC_IP:2087${NC} or ${WHITE}https://$DOMAIN:2087${NC}"
echo -e "${RED}➤ cPanel User (Default SSL) :${NC} ${WHITE}https://$PUBLIC_IP:2083${NC} or ${WHITE}https://$DOMAIN:2083${NC}"
echo -e "${RED}➤ Admin Email              :${NC} ${WHITE}$EMAIL${NC}"
echo -e "${RED}➤ Hostname                 :${NC} ${WHITE}$DOMAIN${NC}"
echo -e "${RED}====================================================${NC}\n"

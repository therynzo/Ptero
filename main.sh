#!/bin/bash

# Setup Colors
RED='\033[0;31m'
NC='\033[0m'
WHITE='\033[1;37m'

clear

# Fetch System Information
RAM=$(free -m | awk '/^Mem:/{print $2}')
CPU=$(grep -m 1 "model name" /proc/cpuinfo | cut -d ':' -f2 | sed 's/^[ \t]*//')
CORES=$(nproc)
DISK=$(df -h / | awk 'NR==2 {print $2}')
IP=$(curl -s -m 3 ifconfig.me || hostname -I | awk '{print $1}')

# Animated Red TheRynzo Banner (Mobile Optimized)
echo -e "${RED}"
cat << "EOF" | while read -r line; do echo "$line"; sleep 0.1; done
 _____ _       ___
|_   _| |_  __| _ \_  _ _ _  ____ ___
  | | | ' \/ -_)   / || | ' \|_  // _ \
  |_| |_||_\___|_|_\_, |_||_| /_/ \___/
                   |__/
EOF
echo -e "${NC}"

# Animated Subtitle
SUBTITLE="Powered By TheRynzo"
echo -e "${RED}"
for (( i=0; i<${#SUBTITLE}; i++ )); do
    echo -n "${SUBTITLE:$i:1}"
    sleep 0.05
done
echo -e "${NC}\n"

# Subtitle: VPS Info (Borders shortened for mobile screens)
echo -e "${RED}======================================${NC}"
echo -e "${WHITE}  SYSTEM INFORMATION${NC}"
echo -e "${RED}======================================${NC}"
echo -e "${RED}➤${NC} ${WHITE}CPU:${NC}  $CPU ($CORES Cores)"
echo -e "${RED}➤${NC} ${WHITE}RAM:${NC}  ${RAM}MB"
echo -e "${RED}➤${NC} ${WHITE}DISK:${NC} $DISK"
echo -e "${RED}➤${NC} ${WHITE}IP:${NC}   $IP"
echo -e "${RED}======================================${NC}"
echo ""

# Options Menu
echo -e "${RED}Please select an installation option:${NC}"
echo -e "${RED}[1]${NC} ${WHITE}Install Pterodactyl Panel${NC}"
echo -e "${RED}[2]${NC} ${WHITE}Install Wings${NC}"
echo -e "${RED}[3]${NC} ${WHITE}Install Cloudflare${NC}"
echo -e "${RED}[4]${NC} ${WHITE}Discord Tools${NC}"
echo -e "${RED}[0]${NC} ${WHITE}Exit${NC}"
echo ""

read -p "$(echo -e ${RED}"Enter choice [1-0]: "${NC})" choice
echo ""

case $choice in
    1)
        echo -e "${RED}➤ Launching Pterodactyl Installer...${NC}"
        sleep 1
        bash <(curl -s https://raw.githubusercontent.com/nobita329/Nobita-Cloud/refs/heads/main/panel/pterodactyl/run.sh)
        ;;
    2)
        echo -e "${RED}➤ Launching Wings Installer...${NC}"
        sleep 1
        bash <(curl -fsSL https://raw.githubusercontent.com/therynzo/Ptero/main/wings.sh)
        ;;
    3)
        echo -e "${RED}➤ Launching Cloudflare Installer...${NC}"
        sleep 1
        bash <(curl -fsSL https://raw.githubusercontent.com/nobita329/ptero/main/ptero/tools/cloudflare.sh)
        ;;
    4)
        echo -e "${RED}➤ Launching Discord Tool' s...${NC}"
        sleep 1
        bash <(curl -fsSL https://raw.githubusercontent.com/therynzo/Ptero/main/bot-menu.sh)
        ;;    
    0)
        echo -e "${RED}➤ Exiting...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}➤ Invalid selection. Exiting...${NC}"
        exit 1
        ;;
esac

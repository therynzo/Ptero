#!/bin/bash
set -e

# ================= COLORS =================
RED='\033[0;31m'
NC='\033[0m' # No Color
# ==========================================

clear

# TheRynzo Animated Banner
echo -e "${RED}"
cat << "EOF" | while read -r line; do echo "$line"; sleep 0.1; done
  _______ _          _____                        
 |__   __| |        |  __ \                       
    | |  | |__   ___| |__) |   _ _ __  _______  
    | |  | '_ \ / _ \  _  / | | | '_ \|__  / _ \ 
    | |  | | | |  __/ | \ \ |_| | | | | / / (_) |
    |_|  |_| |_|\___|_|  \_\__,_|_| |_|/___|\___/ 
EOF
echo -e "${NC}"

echo -e "${RED}================================================================${NC}"
echo -e "${RED}  CLOUDFLARE TUNNEL AUTO-INSTALLER${NC}"
echo -e "${RED}================================================================${NC}\n"

# 1. Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Error: Please run this script as root (sudo).${NC}"
    exit 1
fi

# 2. Prompt for the Cloudflare Token
while true; do
    echo -ne "${RED}➤ Enter your Cloudflare Token: ${NC}"
    read CF_TOKEN
    if [ -z "$CF_TOKEN" ]; then
        echo -e "${RED}✗ Token cannot be empty. Please try again.${NC}"
    else
        break
    fi
done

echo -e "\n${RED}➤ [1/4] Cleaning up broken Cloudflare services...${NC}"
# Use || true to prevent the script from stopping if the service doesn't exist yet
systemctl stop cloudflared > /dev/null 2>&1 || true
cloudflared service uninstall > /dev/null 2>&1 || true
pkill -f cloudflared > /dev/null 2>&1 || true
sleep 1

echo -e "${RED}➤ [2/4] Saving token directly to configuration folder...${NC}"
mkdir -p /etc/cloudflared
echo "$CF_TOKEN" > /etc/cloudflared/token
sleep 1

echo -e "${RED}➤ [3/4] Building clean Systemd service file...${NC}"
cat << 'EOF' > /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflare Tunnel
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel --protocol http2 run --token-file /etc/cloudflared/token
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
sleep 1

echo -e "${RED}➤ [4/4] Starting and enabling the new service...${NC}"
systemctl daemon-reload
systemctl enable cloudflared > /dev/null 2>&1
systemctl start cloudflared
sleep 3

echo -e "\n${RED}================================================================${NC}"
echo -e "${RED}  INSTALLATION COMPLETE!${NC}"
echo -e "${RED}================================================================${NC}\n"

# Check the final status and display it without opening a pager that traps the user
if systemctl is-active --quiet cloudflared; then
    echo -e "${RED}✓ SUCCESS: Cloudflare Tunnel is now active (running)!${NC}"
else
    echo -e "${RED}✗ WARNING: Cloudflare Tunnel failed to start properly.${NC}"
fi

echo -e "\n${RED}➤ Displaying recent service logs:${NC}"
echo -e "${RED}----------------------------------------------------------------${NC}"
systemctl status cloudflared --no-pager -l -n 10 | sed "s/^/$(printf '%b' "$RED")/"
echo -e "${NC}"

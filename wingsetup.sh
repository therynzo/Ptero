#!/bin/bash
set -e

# ================= COLORS =================
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
# =========================================

# TheRynzo BANNER AT START
echo -e ""
echo -e "${RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${RED}┃                   TheRynzo                    ┃${NC}"
echo -e "${RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e "${RED}  _______ _          _____                        ${NC}"
echo -e "${RED} |__   __| |        |  __ \                       ${NC}"
echo -e "${RED}    | |  | |__   ___| |__) |   _ _ __  _______  ${NC}"
echo -e "${RED}    | |  | '_ \ / _ \  _  / | | | '_ \|__  / _ \ ${NC}"
echo -e "${RED}    | |  | | | |  __/ | \ \ |_| | | | | / / (_) |${NC}"
echo -e "${RED}    |_|  |_| |_|\___|_|  \_\__,_|_| |_|/___|\___/ ${NC}"
echo -e ""

print_status() {
    echo -e "${RED}> ${RED}$1...${NC}"
}

check_success() {
    echo -e "${RED}[OK] ${RED}$1${NC}"
}

echo -e "${RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${RED}┃             AUTO-CONFIGURING WINGS            ┃${NC}"
echo -e "${RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e ""

# Function to go back to previous input
go_back() {
    echo -e "${RED}  Going back to previous step...${NC}"
}

echo -e "${RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${RED}┃            WINGS AUTO-CONFIGURATION           ┃${NC}"
echo -e "${RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e ""

echo -e "${RED}┌─────────────────────────────────────────────┐${NC}"
echo -e "${RED}│   Please provide Pterodactyl panel details  │${NC}"
echo -e "${RED}│   (type 'back' to go to previous field)     │${NC}"
echo -e "${RED}└─────────────────────────────────────────────┘${NC}"
echo -e ""

# Collect configuration with back option
while true; do
    echo -ne "${RED}  Enter UUID: ${NC}"
    read UUID
    
    if [ "$UUID" = "back" ]; then
        echo -e "${RED}  Cannot go back from first field${NC}"
        continue
    elif [ -z "$UUID" ]; then
        echo -e "${RED}  UUID cannot be empty${NC}"
        continue
    else
        break
    fi
done

while true; do
    echo -ne "${RED}  Enter Token ID: ${NC}"
    read TOKEN_ID
    
    if [ "$TOKEN_ID" = "back" ]; then
        echo -ne "${RED}  Enter UUID [$UUID]: ${NC}"
        read NEW_UUID
        if [ -n "$NEW_UUID" ]; then
            UUID="$NEW_UUID"
        fi
        continue
    elif [ -z "$TOKEN_ID" ]; then
        echo -e "${RED}  Token ID cannot be empty${NC}"
        continue
    else
        break
    fi
done

while true; do
    echo -ne "${RED}  Enter Token: ${NC}"
    read TOKEN
    
    if [ "$TOKEN" = "back" ]; then
        echo -ne "${RED}  Enter Token ID [$TOKEN_ID]: ${NC}"
        read NEW_TOKEN_ID
        if [ -n "$NEW_TOKEN_ID" ]; then
            TOKEN_ID="$NEW_TOKEN_ID"
        fi
        continue
    elif [ -z "$TOKEN" ]; then
        echo -e "${RED}  Token cannot be empty${NC}"
        continue
    else
        break
    fi
done

while true; do
    echo -ne "${RED}  Enter Panel URL (https://panel.example.com): ${NC}"
    read REMOTE
    
    if [ "$REMOTE" = "back" ]; then
        echo -ne "${RED}  Enter Token [$TOKEN]: ${NC}"
        read NEW_TOKEN
        if [ -n "$NEW_TOKEN" ]; then
            TOKEN="$NEW_TOKEN"
        fi
        continue
    elif [ -z "$REMOTE" ]; then
        echo -e "${RED}  Using default URL: https://panel.example.com${NC}"
        REMOTE="https://panel.example.com"
        break
    elif [[ ! "$REMOTE" =~ ^https?:// ]]; then
        echo -e "${RED}  Please enter a valid URL starting with http:// or https://${NC}"
        continue
    else
        break
    fi
done

# Show confirmation
echo -e ""
echo -e "${RED}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${RED}│               CONFIGURATION REVIEW               │${NC}"
echo -e "${RED}├──────────────────────────────────────────────────┤${NC}"
echo -e "${RED}│  UUID:       ${UUID}${NC}"
echo -e "${RED}│  Token ID:   ${TOKEN_ID}${NC}"
echo -e "${RED}│  Panel URL:  ${REMOTE}${NC}"
echo -e "${RED}└──────────────────────────────────────────────────┘${NC}"
echo -e ""

# Ask for confirmation
echo -ne "${RED}  Is this information correct? [Y/n/back]: ${NC}"
read CONFIRM

if [[ "$CONFIRM" =~ ^[Bb]ack$ ]]; then
    echo -e "${RED}  Going back to URL field...${NC}"
    while true; do
        echo -ne "${RED}  Enter Panel URL [$REMOTE]: ${NC}"
        read NEW_REMOTE
        if [ "$NEW_REMOTE" = "back" ]; then
            echo -e "${RED}  Going back to Token field...${NC}"
            while true; do
                echo -ne "${RED}  Enter Token [$TOKEN]: ${NC}"
                read NEW_TOKEN
                if [ "$NEW_TOKEN" = "back" ]; then
                    echo -e "${RED}  Going back to Token ID field...${NC}"
                    while true; do
                        echo -ne "${RED}  Enter Token ID [$TOKEN_ID]: ${NC}"
                        read NEW_TOKEN_ID
                        if [ "$NEW_TOKEN_ID" = "back" ]; then
                            echo -e "${RED}  Going back to UUID field...${NC}"
                            echo -ne "${RED}  Enter UUID [$UUID]: ${NC}"
                            read NEW_UUID
                            if [ -n "$NEW_UUID" ]; then
                                UUID="$NEW_UUID"
                            fi
                            break
                        elif [ -n "$NEW_TOKEN_ID" ]; then
                            TOKEN_ID="$NEW_TOKEN_ID"
                            break
                        else
                            echo -e "${RED}  Token ID cannot be empty${NC}"
                        fi
                    done
                    continue
                elif [ -n "$NEW_TOKEN" ]; then
                    TOKEN="$NEW_TOKEN"
                    break
                else
                    echo -e "${RED}  Token cannot be empty${NC}"
                fi
            done
            continue
        elif [ -n "$NEW_REMOTE" ]; then
            REMOTE="$NEW_REMOTE"
            break
        else
            break
        fi
    done
elif [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo -e "${RED}  Configuration cancelled${NC}"
    echo -e "${RED}Please run the script again with correct details.${NC}"
    exit 1
fi

echo -e ""
echo -e "${RED}┌─────────────────────────────────────────────┐${NC}"
echo -e "${RED}│     Creating Wings configuration...         │${NC}"
echo -e "${RED}└─────────────────────────────────────────────┘${NC}"

print_status "Creating directory structure"
mkdir -p /etc/pterodactyl

print_status "Generating config.yml"
if ! tee /etc/pterodactyl/config.yml > /dev/null <<CFG
debug: false
uuid: ${UUID}
token_id: ${TOKEN_ID}
token: ${TOKEN}
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: true
    cert: /etc/certs/wing/fullchain.pem
    key: /etc/certs/wing/privkey.pem
  upload_limit: 100
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_port: 2022
allowed_mounts: []
remote: '${REMOTE}'
CFG
then
    echo -e "${RED}  Failed to create configuration file${NC}"
    exit 1
fi

echo -e "${RED}  Configuration saved to /etc/pterodactyl/config.yml${NC}"

echo -e ""
echo -e "${RED}┌─────────────────────────────────────────────┐${NC}"
echo -e "${RED}│         Starting Wings service...           │${NC}"
echo -e "${RED}└─────────────────────────────────────────────┘${NC}"

print_status "Enabling Wings service"
if ! systemctl enable wings 2>/dev/null; then
    echo -e "${RED}  Could not enable Wings service (may already be enabled)${NC}"
fi

print_status "Starting Wings service"
if systemctl restart wings 2>/dev/null; then
    # Verify service is running
    sleep 3
    if systemctl is-active --quiet wings; then
        echo -e "${RED}  Wings service started successfully${NC}"
    else
        echo -e "${RED}  Wings service failed to start${NC}"
        echo -e "${RED}Checking logs...${NC}"
        journalctl -u wings --no-pager -n 10
        exit 1
    fi
else
    echo -e "${RED}  Failed to start Wings service${NC}"
    exit 1
fi

echo -e ""
echo -e "${RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${RED}┃             CONFIGURATION COMPLETE            ┃${NC}"
echo -e "${RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e ""

# Quick reference
echo -e ""
echo -e "${RED}┌─────────────────────────────────────────────┐${NC}"
echo -e "${RED}│                 QUICK COMMANDS              │${NC}"
echo -e "${RED}└─────────────────────────────────────────────┘${NC}"
echo -e "${RED}  Check status:  systemctl status wings${NC}"
echo -e "${RED}  View logs:     journalctl -u wings -f${NC}"
echo -e "${RED}  Restart:       systemctl restart wings${NC}"
echo -e "${RED}  Config edit:   nano /etc/pterodactyl/config.yml${NC}"

echo -e ""
echo -e "${RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${RED}┃           THANK YOU FOR CHOOSING              ┃${NC}"
echo -e "${RED}┃                 TheRynzo!                     ┃${NC}"
echo -e "${RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e ""

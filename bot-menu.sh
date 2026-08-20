#!/bin/bash
set -e

# Setup Colors
RED='\033[0;31m'
NC='\033[0m'
WHITE='\033[1;37m'

clear

# Animated Red Banner (Stacked & Boxed for Mobile)
echo -e "${RED}"
cat << "EOF" | while read -r line; do echo "$line"; sleep 0.05; done
┌────────────────────────────────────┐
│  ___  _                       _    │
│ |  _ \(_)___  ___ ___ _ __ __| |   │
│ | | | | / __|/ __/ _ \ '__/ _` |   │
│ | |_| | \__ \ (_|  __/ | | (_| |   │
│ |____/|_|___/\___\___|_|  \__,_|   │
│  _____           _                 │
│ |_   _|__   ___ | |___             │
│   | |/ _ \ / _ \| / __|            │
│   | | (_) | (_) | \__ \            │
│   |_|\___/ \___/|_|___/            │
└────────────────────────────────────┘
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

# Options Menu
echo -e "${RED}======================================${NC}"
echo -e "${RED}Please select an option:${NC}"
echo -e "${RED}[1]${NC} ${WHITE}Server Clone Setup${NC}"
echo -e "${RED}[0]${NC} ${WHITE}Exit${NC}"
echo -e "${RED}======================================${NC}"
echo ""

read -p "$(echo -e ${RED}"Enter choice [1-0]: "${NC})" choice
echo ""

case $choice in
    1)
        echo -e "${RED}➤${NC} ${WHITE}Launching Server Clone Setup...${NC}\n"
        sleep 1
        bash <(curl -fsSL https://raw.githubusercontent.com/therynzo/Server-Clone/main/run.sh)
        ;;
    0)
        echo -e "${RED}➤${NC} ${WHITE}Exiting...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}➤${NC} ${WHITE}Invalid selection. Exiting...${NC}"
        exit 1
        ;;
esac

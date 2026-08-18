#!/bin/bash
# ==========================================
# TheRynzo Premium MOTD Installer (v3 PRO)
# FULL CLEAN + ONLY CUSTOM MOTD
# ==========================================

set -e

echo "🔧 Installing TheRynzo Premium MOTD..."

# ================================
# REMOVE ALL OLD MOTD SYSTEM
# ================================
echo "🧹 Removing old MOTD completely..."

# Disable all default MOTD scripts
chmod -x /etc/update-motd.d/* 2>/dev/null || true

# Remove default files
rm -f /etc/motd
rm -f /var/run/motd
rm -f /run/motd.dynamic

# Disable motd-news
if [ -f /etc/default/motd-news ]; then
    sed -i 's/ENABLED=1/ENABLED=0/g' /etc/default/motd-news
fi

# ================================
# FORCE ONLY OUR MOTD (PAM FIX)
# ================================
echo "⚙ Configuring PAM..."

# Backup PAM files (safe)
cp /etc/pam.d/sshd /etc/pam.d/sshd.bak 2>/dev/null || true
cp /etc/pam.d/login /etc/pam.d/login.bak 2>/dev/null || true

# Remove old motd lines
sed -i '/pam_motd.so/d' /etc/pam.d/sshd
sed -i '/pam_motd.so/d' /etc/pam.d/login

# Add ONLY our MOTD
echo "session optional pam_exec.so stdout /etc/update-motd.d/00-therynzo" >> /etc/pam.d/sshd
echo "session optional pam_exec.so stdout /etc/update-motd.d/00-therynzo" >> /etc/pam.d/login

# ================================
# CREATE PREMIUM MOTD SCRIPT
# ================================
echo "✨ Creating TheRynzo MOTD..."

cat << 'EOF' > /etc/update-motd.d/00-therynzo
#!/bin/bash

# ===== Colors =====
RED="\e[31m"
RESET="\e[0m"

# ===== System Info (Optimized) =====
HOSTNAME=$(hostname)
OS=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)
UPTIME=$(uptime -p | sed 's/up //')
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')

MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_PERC=$((MEM_USED * 100 / MEM_TOTAL))

DISK=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')

IP=$(hostname -I | awk '{print $1}')
USERS=$(who | wc -l)
PROCS=$(ps -e --no-headers | wc -l)

echo ""

# ===== LOGO =====
echo -e "${RED}"
cat << "LOGO"
  _______ _          _____                        
 |__   __| |        |  __ \                       
    | |  | |__   ___| |__) |   _ _ __  _______  
    | |  | '_ \ / _ \  _  / | | | '_ \|__  / _ \ 
    | |  | | | |  __/ | \ \ |_| | | | | / / (_) |
    |_|  |_| |_|\___|_|  \_\__,_|_| |_|/___|\___/ 
LOGO
echo -e "${RESET}"

# ===== HEADER =====
echo -e "${RED}🚀 Welcome to TheRynzo Datacenter${RESET}"
echo -e "${RED}High Performance • Secure • Reliable Infrastructure${RESET}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ===== STATS =====
printf "${RED}%-18s${RESET} %s\n" "Hostname:" "$HOSTNAME"
printf "${RED}%-18s${RESET} %s\n" "OS:" "$OS"
printf "${RED}%-18s${RESET} %s\n" "Kernel:" "$KERNEL"
printf "${RED}%-18s${RESET} %s\n" "Uptime:" "$UPTIME"
printf "${RED}%-18s${RESET} %s\n" "CPU Usage:" "$CPU"
printf "${RED}%-18s${RESET} %sMB / %sMB (${RED}%s%%${RESET})\n" "Memory:" "$MEM_USED" "$MEM_TOTAL" "$MEM_PERC"
printf "${RED}%-18s${RESET} %s\n" "Disk:" "$DISK"
printf "${RED}%-18s${RESET} %s\n" "Processes:" "$PROCS"
printf "${RED}%-18s${RESET} %s\n" "Users:" "$USERS"
printf "${RED}%-18s${RESET} %s\n" "IP:" "$IP"

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ===== FOOTER =====
echo -e "${RED}Support:${RESET}  support@therynzo.cloud"
echo -e "${RED}Discord:${RESET}  https://discord.gg/RTcr3gmQFr"
echo -e "${RED}Website:${RESET}  https://therynzo.cloud"
echo -e "${RED}TheRynzo — Premium Hosting Experience 💎${RESET}"
echo ""
EOF

chmod +x /etc/update-motd.d/00-therynzo

# ================================
# RESTART SERVICES
# ================================
systemctl restart ssh 2>/dev/null || true

echo ""
echo "✅ TheRynzo MOTD Installed (ONLY MODE ENABLED)"
echo "🚫 All default MOTD fully removed"
echo "🔥 Only your custom MOTD will show"
echo "➡ Reconnect SSH to see changes"

#!/usr/bin/env bash
# Official cPanel & WHM menu helper for Ubuntu 22.04 LTS.
# This script does not bypass, extend, or remove cPanel licensing.
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
info(){ echo -e "${GREEN}[INFO]${RESET} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail(){ echo -e "${RED}[ERROR]${RESET} $*" >&2; }
pause(){ read -r -p "Press Enter to continue..." _; }

check_root() {
  if [[ ${EUID} -ne 0 ]]; then
    fail "Run as root: sudo bash $0"
    return 1
  fi
}

check_os() {
  [[ -r /etc/os-release ]] || { fail "Cannot identify operating system."; return 1; }
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != ubuntu || "${VERSION_ID:-}" != "22.04" ]]; then
    fail "This script is specifically for Ubuntu 22.04 LTS. Detected: ${PRETTY_NAME:-unknown}"
    return 1
  fi
  if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    fail "cPanel requires a supported x86_64/amd64 server."
    return 1
  fi
}

show_status() {
  echo
  if [[ -x /usr/local/cpanel/cpanel ]]; then
    info "cPanel files detected."
    /usr/local/cpanel/cpanel -V 2>/dev/null || true
  else
    warn "cPanel installation was not detected at /usr/local/cpanel."
  fi

  if command -v systemctl >/dev/null 2>&1; then
    echo
    systemctl --no-pager --full status cpanel 2>&1 | head -n 18 || true
  fi
  echo
  echo "WHM normally uses: https://SERVER-IP:2087"
}

install_cpanel() {
  check_root || return
  check_os || return

  if [[ -x /usr/local/cpanel/cpanel ]]; then
    warn "cPanel appears to already be installed. Not running the installer again."
    show_status
    return
  fi

  local ram_gb free_gb fqdn confirm
  ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')

  echo
  echo "Detected Ubuntu 22.04 LTS / amd64."
  echo "cPanel's published compatibility table lists Ubuntu 22.04 for cPanel 134,"
  echo "but not cPanel 136 or later. The official installer chooses what it supports."
  echo "Do not try to force an incompatible release."
  echo
  echo "Approximate RAM: ${ram_gb} GB"
  echo "Free space on /: ${free_gb} GB"
  (( ram_gb >= 2 )) || { fail "At least 2 GB RAM is required; more is recommended."; return; }
  (( free_gb >= 20 )) || { fail "At least 20 GB free space on / is required; more is recommended."; return; }

  echo
  read -r -p "Enter a fully-qualified hostname (e.g. server.example.com): " fqdn
  [[ "$fqdn" =~ ^(([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)\.)+[a-zA-Z]{2,}$ ]] || {
    fail "Invalid hostname. Use a fully-qualified domain name."
    return
  }

  echo
  warn "Install only on a freshly installed OS. Existing websites/data may be affected."
  warn "Use a public static IPv4 address with correct forward and reverse DNS."
  warn "A valid paid cPanel license or official trial is still required."
  echo
  read -r -p 'Type INSTALL to start the official cPanel installer: ' confirm
  [[ "$confirm" == "INSTALL" ]] || { warn "Installation cancelled."; return; }

  export DEBIAN_FRONTEND=noninteractive
  info "Setting hostname..."
  hostnamectl set-hostname "$fqdn"

  info "Installing prerequisites..."
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates perl

  info "Downloading the official cPanel installer over HTTPS..."
  install -d -m 0755 /home
  curl --fail --location --show-error --proto '=https' --tlsv1.2 \
    -o /home/latest https://securedownloads.cpanel.net/latest
  [[ -s /home/latest ]] || { fail "Official installer download is empty."; return; }

  info "Starting official cPanel installation. This can take a long time."
  (cd /home && sh /home/latest)

  info "Installer process returned. Review its output for errors."
  echo "WHM URL: https://$(hostname -I | awk '{print $1}'):2087"
  echo "Complete setup and activate an official trial or paid license."
}

uninstall_info() {
  check_root || return
  echo
  echo "cPanel & WHM does not provide a supported full uninstaller."
  echo "Official removal requires backing up your data and reinstalling/reformatting"
  echo "the server operating system from your VPS provider's control panel."
  echo
  echo "This menu option intentionally does NOT delete cPanel folders or packages:"
  echo "manual deletion can leave services, databases, firewall rules, and packages"
  echo "broken, and can damage the operating system."
  echo
  warn "Before rebuilding, back up all accounts, websites, databases, mail, DNS,"
  echo "SSL certificates, and configuration. Confirm that the backup is restorable."
  echo
  echo "To remove cPanel safely:"
  echo "  1. Create and verify backups."
  echo "  2. Open your VPS provider's panel."
  echo "  3. Choose Reinstall OS / Rebuild VPS."
  echo "  4. Select the desired clean operating system."
  echo "  5. Restore your data and install your chosen control panel."
  echo
  read -r -p "Type REBUILD to acknowledge these instructions, or press Enter to return: " confirm
  if [[ "$confirm" == "REBUILD" ]]; then
    warn "No changes were made. Start the OS rebuild from your VPS provider's panel."
  fi
}

menu() {
  while true; do
    clear 2>/dev/null || true
    echo -e "${CYAN}====================================================${RESET}"
    echo -e "${CYAN}       cPanel & WHM Ubuntu 22.04 Manager${RESET}"
    echo -e "${CYAN}====================================================${RESET}"
    echo "  1) Install cPanel (official installer)"
    echo "  2) Uninstall cPanel (safe removal instructions)"
    echo "  3) Check cPanel installation/status"
    echo "  4) Exit"
    echo
    read -r -p "Select an option [1-4]: " choice
    case "$choice" in
      1) install_cpanel; pause ;;
      2) uninstall_info; pause ;;
      3) show_status; pause ;;
      4) exit 0 ;;
      *) warn "Invalid option."; pause ;;
    esac
  done
}

check_root || exit 1
menu

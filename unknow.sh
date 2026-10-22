#!/usr/bin/env bash
set -Eeuo pipefail

# DezerX Theme Setup — SKA & SPARK
# Menu-driven launcher. Intended for a Pterodactyl Panel installation.

BLUE=$'\033[1;34m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
WHITE=$'\033[1;97m'
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
NC=$'\033[0m'

PANEL_DIR="/var/www/pterodactyl"
THEME_URL="https://github.com/coding-ultra/Info2/raw/main/theme.zip"
WORK_DIR="/tmp/dezerx-theme-setup"

show_banner() {
  clear 2>/dev/null || true
  printf '%s' "$BLUE"
  cat <<'BANNER'
#     ________       ___
#    /_  __/ /  ___ / _ \__ _____  ___ ___
#     / / / _ \/ -_) , _/ // / _ \/_ // _ \
#    /_/ /_//_/\__/_/|_|\_, /_//_//__/\___/
#                      /___/
BANNER
  printf '%s\n' "$NC"
}

pause_for_enter() {
  read -r -p "Press Enter to return to the menu..." _ || true
}

install_theme() {
  local confirm backup_path installer_status=0

  echo -e "${GREEN}>>> Starting DezerX Theme Setup by SKA & SPARK...${NC}\n"

  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Please run this script as root (sudo).${NC}"
    return 1
  fi

  if [[ ! -d "$PANEL_DIR" || ! -f "$PANEL_DIR/artisan" || ! -f "$PANEL_DIR/public/index.php" ]]; then
    echo -e "${RED}Pterodactyl panel was not found at $PANEL_DIR.${NC}"
    echo "No installation was started. Check PANEL_DIR in this script if your panel is elsewhere."
    return 1
  fi

  for dep in curl unzip; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo -e "${RED}Missing dependency: $dep${NC}"
      return 1
    fi
  done

  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"

  echo -e "${YELLOW}[1/3] Downloading and checking theme archive...${NC}"
  if ! curl -fL --retry 2 --connect-timeout 15 "$THEME_URL" -o theme.zip; then
    echo -e "${RED}Theme download failed.${NC}"
    return 1
  fi

  if ! unzip -tq theme.zip; then
    echo -e "${RED}The downloaded file is not a valid ZIP archive.${NC}"
    return 1
  fi

  # Extract into a fresh directory so stale files cannot be picked up accidentally.
  rm -rf "$WORK_DIR/extracted"
  mkdir -p "$WORK_DIR/extracted"
  if ! unzip -oq theme.zip -d "$WORK_DIR/extracted"; then
    echo -e "${RED}Theme extraction failed.${NC}"
    return 1
  fi

  if [[ ! -f "$WORK_DIR/extracted/install.sh" ]]; then
    echo -e "${RED}install.sh was not found at the archive root.${NC}"
    echo "Review the ZIP layout before continuing; nothing was installed."
    return 1
  fi

  echo -e "${YELLOW}Review the installer at: $WORK_DIR/extracted/install.sh${NC}"
  echo -e "${YELLOW}It will run with root privileges and may modify your panel.${NC}"
  read -r -p "Continue with theme installation? [y/N]: " confirm || true
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation cancelled."
    return 0
  fi

  # Back up this installation's own index.php BEFORE the theme installer runs.
  backup_path="$PANEL_DIR/public/index.php.pre-dezerx-$(date +%Y%m%d-%H%M%S)"

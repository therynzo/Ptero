  command -v unzip >/dev/null 2>&1 || { echo "Missing dependency: unzip"; return 1; }
  command -v curl >/dev/null 2>&1 || { echo "Missing dependency: curl"; return 1; }

  local workdir="/tmp/dezerx-theme-setup"
  mkdir -p "$workdir"
  cd "$workdir"

  wget -q --show-progress "https://github.com/coding-ultra/Info2/raw/main/theme.zip" -O theme.zip || {
    echo -e "${RED}Theme download failed.${NC}"; return 1;
  }

  unzip -o theme.zip || { echo -e "${RED}Theme extraction failed.${NC}"; return 1; }
  [[ -f install.sh ]] || { echo -e "${RED}install.sh was not found in the archive.${NC}"; return 1; }

  echo -e "${YELLOW}The downloaded install.sh will run as root. Continue only if you trust its contents.${NC}"
  read -rp "Run install.sh now? [y/N]: " confirm
  [[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "Installation cancelled."; return 0; }

  bash install.sh || { echo -e "${RED}Theme install.sh failed.${NC}"; return 1; }

  echo -e "\n${YELLOW}[2/3] Restoring default Pterodactyl index.php...${NC}"
  cd /var/www/pterodactyl || { echo -e "${RED}Pterodactyl directory not found: /var/www/pterodactyl${NC}"; return 1; }
  if [[ -f public/index.php ]]; then
    cp -a public/index.php "public/index.php.backup.$(date +%Y%m%d-%H%M%S)"
  fi
  curl -fsSL "https://raw.githubusercontent.com/pterodactyl/panel/master/public/index.php" -o public/index.php || {
    echo -e "${RED}Could not download default index.php; your backup was preserved.${NC}"; return 1;
  }

  echo -e "${YELLOW}[3/3] Fixing panel permissions...${NC}"
  chown -R www-data:www-data /var/www/pterodactyl 2>/dev/null || true
  chown -R nginx:nginx /var/www/pterodactyl 2>/dev/null || true
  find /var/www/pterodactyl -type d -exec chmod 755 {} \;
  find /var/www/pterodactyl -type f -exec chmod 644 {} \;
  [[ -d storage ]] && chmod -R 775 storage/* 2>/dev/null || true
  [[ -d bootstrap/cache ]] && chmod -R 775 bootstrap/cache/ 2>/dev/null || true
  chown -R www-data:www-data /var/www/pterodactyl/ 2>/dev/null || true

  echo -e "\n${GREEN}>>> Setup finished. Please test your panel and review the installer output.${NC}"
}

if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}Error: Please run as root (use sudo).${NC}"
  exit 1
fi

while true; do
  show_banner
  echo -e "${CYAN}==========================================${NC}"
  echo -e "${WHITE}          DEZERX THEME SETUP MENU${NC}"
  echo -e "${CYAN}==========================================${NC}"
  echo -e "${GREEN}1)${NC} Start theme installation"
  echo -e "${RED}0)${NC} Exit"
  echo
  read -rp "Choose an option: " choice
  case "$choice" in
    1)
      install_theme
      read -rp "Press Enter to return to the menu..." _
      ;;
    0)
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid option. Enter 1 to install or 0 to exit.${NC}"
      sleep 1
      ;;
  esac
done

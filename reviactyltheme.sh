#!/usr/bin/env bash
# =====================================================================
# TheRynzo Reviactyl Installer & Recovery (hardened archive handling and compatibility gate)
# Ubuntu/Debian | PHP 8.3+ | Existing Pterodactyl -> Reviactyl migration
#
# IMPORTANT: Reviactyl is a panel replacement/fork, NOT a CSS-only theme.
# This script backs up files + database, prepares dependencies in a staging
# directory, and only then switches the live application.
# =====================================================================

set -Eeuo pipefail
IFS=$'\n\t'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
BACKUP_ROOT="${BACKUP_ROOT:-/root/reviactyl-backups}"
PANEL_DOMAIN="${PANEL_DOMAIN:-}"
RELEASE_URL="https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz"
WORK_DIR=""
BACKUP_DIR=""
OLD_DIR=""
PHP_VERSION=""
DB_CONNECTION=""
DB_HOST=""
DB_PORT=""
DB_DATABASE=""
DB_USERNAME=""
DB_PASSWORD=""
MYSQL_BIN=""
DUMP_BIN=""

RESET=$'\033[0m'
WHITE=$'\033[1;37m'
RED=$'\033[38;2;255;70;70m'
RED2=$'\033[38;2;230;55;55m'
RED3=$'\033[38;2;150;15;35m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;36m'
GRAY=$'\033[0;90m'

info() { printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b[WARNING]%b %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$*" >&2; }
pause_menu() { printf '\n'; read -r -p 'Press ENTER to return to the menu...' _ || true; }

banner() {
    clear 2>/dev/null || true
    printf '%b' "$RED"
    printf '  _____ _   _ _____ ____  _____ _   _ _____ ___\n'
    printf '%b' "$RED2"
    printf ' |_   _| | | | ____|  _ \\|_   _| | | |_   _/ _ \\\n'
    printf '   | | | |_| |  _| | |_) | | | | |_| | | || | | |\n'
    printf '%b' "$RED3"
    printf '   | | |  _  | |___|  _ <  | | |  _  | | || |_| |\n'
    printf '   |_| |_| |_|_____|_| \\_\\ |_| |_| |_| |_| \\___/\n'
    printf '%b       REVIACTYL INSTALLER & RECOVERY%b\n' "$WHITE" "$RESET"
    printf '%b             Made by TheRynzo%b\n' "$RED" "$RESET"
    printf '%b================================================%b\n' "$RED" "$RESET"
    printf '%bPanel:  %b%s%b\n' "$BLUE" "$WHITE" "$PANEL_DIR" "$RESET"
    printf '%bDomain: %b%s%b\n\n' "$BLUE" "$WHITE" "${PANEL_DOMAIN:-read from APP_URL}" "$RESET"
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        fail 'Run as root. Example: sudo bash reviactyltheme.sh'
        exit 1
    fi
}

check_os() {
    [[ -r /etc/os-release ]] || { fail 'Cannot identify this operating system.'; return 1; }
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian) info "Detected OS: ${PRETTY_NAME:-$ID}" ;;
        *) fail "This script supports Ubuntu/Debian; detected ${PRETTY_NAME:-unknown}."; return 1 ;;
    esac
}

choose_panel_dir() {
    local entered
    read -r -p "Panel directory [$PANEL_DIR]: " entered || true
    entered="${entered:-$PANEL_DIR}"
    entered="${entered%/}"
    [[ -n "$entered" && "$entered" == /* && "$entered" != "/" ]] || {
        fail 'Enter a valid absolute path (not /).'; return 1;
    }
    PANEL_DIR="$entered"
    [[ -d "$PANEL_DIR" && ! -L "$PANEL_DIR" ]] || { fail "Panel directory missing or is a symlink: $PANEL_DIR"; return 1; }
}

check_panel() {
    [[ -f "$PANEL_DIR/artisan" && -f "$PANEL_DIR/composer.json" && -f "$PANEL_DIR/.env" && -f "$PANEL_DIR/vendor/autoload.php" ]] || {
        fail "An initialized Laravel panel was not found at $PANEL_DIR (artisan, composer.json, .env and vendor/autoload.php are required)."

#!/usr/bin/env bash
# ==========================================================
#  THERYNZO REVIACTYL INSTALLER
#  Install / Migrate / Restore
#  Panel: /var/www/pterodactyl
#  Domain: gp.aliennode.in
# ==========================================================

set -Eeuo pipefail

# ---------- CONFIGURATION ----------
DEFAULT_PANEL_DIR="/var/www/pterodactyl"
DEFAULT_DOMAIN="gp.aliennode.in"
BACKUP_ROOT="/root/reviactyl-backups"
RELEASE_URL="https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz"

RED='\033[1;31m'
LIGHT_RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
RESET='\033[0m'

TMP_DIR=""
INSTALL_IN_PROGRESS=0
PANEL_DIR=""
BACKUP_DIR=""
DB_CONNECTION=""
DB_HOST=""
DB_PORT=""
DB_DATABASE=""
DB_USERNAME=""
DB_PASSWORD=""
MYSQL_BIN=""
DUMP_BIN=""
OLD_DIR=""

# ---------- DISPLAY ----------
banner() {
    clear 2>/dev/null || true

    echo -e "${RED}"
    echo "  ████████╗██╗  ██╗███████╗"
    echo "  ╚══██╔══╝██║  ██║██╔════╝"
    echo "     ██║   ███████║█████╗"
    echo "     ██║   ██╔══██║██╔══╝"
    echo "     ██║   ██║  ██║███████╗"
    echo "     ╚═╝   ╚═╝  ╚═╝╚══════╝"
    echo -e "${LIGHT_RED}       REVIACTYL INSTALLER${RESET}"
    echo -e "${GRAY}       Made By TheRynzo${RESET}"
    echo
    echo -e "${CYAN}  Reviactyl Panel Installer & Recovery${RESET}"
    echo -e "${GRAY}  ------------------------------------${RESET}"
    echo
}

msg() {
    echo -e "${CYAN}[INFO]${RESET} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${RESET} $*"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}

pause_screen() {
    echo
    read -r -p "Press ENTER to continue..."
}

# ---------- SAFETY CHECKS ----------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Run this script as root."
        echo "Example: sudo bash reviactyltheme.sh"
        exit 1
    fi
}

check_tools() {
    local missing=()

    for command_name in curl tar python3 php; do
        command -v "$command_name" >/dev/null 2>&1 ||
            missing+=("$command_name")
    done

    if ((${#missing[@]} > 0)); then
        error "Missing required tools: ${missing[*]}"
        echo "Install the missing tools before running this script."
        exit 1
    fi
}

ask_panel_path() {
    echo
    read -r -p "Panel directory [$DEFAULT_PANEL_DIR]: " PANEL_DIR
    PANEL_DIR="${PANEL_DIR:-$DEFAULT_PANEL_DIR}"
    PANEL_DIR="${PANEL_DIR%/}"

    if [[ -z "$PANEL_DIR" || "$PANEL_DIR" != /* ]]; then
        error "Please use an absolute panel directory."
        return 1
    fi

    if [[ "$PANEL_DIR" == "/" ]]; then
        error "The root directory cannot be used as a panel directory."
        return 1
    fi

    if [[ -L "$PANEL_DIR" ]]; then
        error "The panel directory is a symbolic link. Check its real path first."
        return 1
    fi

    if [[ ! -d "$PANEL_DIR" ]]; then
        error "Panel directory does not exist: $PANEL_DIR"
        return 1
    fi

    if [[ ! -f "$PANEL_DIR/.env" ||
          ! -f "$PANEL_DIR/artisan" ||
          ! -f "$PANEL_DIR/composer.json" ]]; then
        error "This does not look like a Laravel panel installation."
        return 1
    fi
}

# ---------- READ .ENV SAFELY ----------
read_database_settings() {
    local env_file="$1"
    local -a values=()

    if [[ ! -f "$env_file" ]]; then
        error "Cannot find .env file: $env_file"
        return 1
    fi

    mapfile -t values < <(
        python3 - "$env_file" <<'PY'
import sys

path = sys.argv[1]
wanted = [
    "DB_CONNECTION",
    "DB_HOST",
    "DB_PORT",
    "DB_DATABASE",
    "DB_USERNAME",
    "DB_PASSWORD",
]
found = {}

with open(path, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()

        if key not in wanted:
            continue

        value = value.strip()

        if (
            len(value) >= 2
            and value[0] == value[-1]
            and value[0] in ("'", '"')
        ):
            value = value[1:-1]

        found[key] = value

for key in wanted:
    print(found.get(key, ""))
PY
    )

    DB_CONNECTION="${values[0]:-mysql}"
    DB_HOST="${values[1]:-127.0.0.1}"
    DB_PORT="${values[2]:-3306}"
    DB_DATABASE="${values[3]:-}"
    DB_USERNAME="${values[4]:-}"
    DB_PASSWORD="${values[5]:-}"

    if [[ "$DB_CONNECTION" != "mysql" && "$DB_CONNECTION" != "mariadb" ]]; then
        error "This script currently supports MySQL/MariaDB databases only."
        error "Detected DB_CONNECTION=$DB_CONNECTION"
        return 1
    fi

    if [[ -z "$DB_DATABASE" || -z "$DB_USERNAME" ]]; then
        error "DB_DATABASE or DB_USERNAME is missing from .env."
        return 1
    fi

    MYSQL_BIN="$(command -v mariadb || command -v mysql || true)"
    DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump || true)"

    if [[ -z "$MYSQL_BIN" || -z "$DUMP_BIN" ]]; then
        error "MySQL/MariaDB client and database dump utility are required."
        return 1
    fi
}

# ---------- VERSION CHECK ----------
check_php_version() {
    local version major minor

    version="$(php -r 'echo PHP_VERSION;' 2>/dev/null)" || {
        error "Unable to detect the PHP version."
        return 1
    }

    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%.*}"

    msg "Detected PHP version: $version"

    if (( major < 8 || (major == 8 && minor < 3) )); then
        error "The current Reviactyl release requires PHP 8.3 or newer."
        error "Upgrade PHP and its required extensions before migrating."
        return 1
    fi
}

# ---------- BACKUP ----------
create_backup() {
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$BACKUP_ROOT"
    chmod 700 "$BACKUP_ROOT"

    BACKUP_DIR="$BACKUP_ROOT/$timestamp"

    if [[ -e "$BACKUP_DIR" ]]; then
        error "Backup path already exists: $BACKUP_DIR"
        return 1
    fi

    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    echo "$PANEL_DIR" > "$BACKUP_DIR/panel_path.txt"
    chmod 600 "$BACKUP_DIR/panel_path.txt"

    msg "Creating complete panel file backup..."
    msg "This can take some time if your panel contains many files."

    if ! tar -czpf "$BACKUP_DIR/panel-files.tar.gz" \
        -C "$(dirname "$PANEL_DIR")" \
        "$(basename "$PANEL_DIR")"; then
        error "Panel file backup failed."
        return 1
    fi

    chmod 600 "$BACKUP_DIR/panel-files.tar.gz"

    msg "Backing up database: $DB_DATABASE"

    if ! MYSQL_PWD="$DB_PASSWORD" "$DUMP_BIN" \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_USERNAME" \
        --single-transaction \
        --routines \
        --triggers \
        "$DB_DATABASE" > "$BACKUP_DIR/database.sql"; then
        rm -f "$BACKUP_DIR/database.sql"
        error "Database backup failed. Migration will not continue."
        return 1
    fi

    if [[ ! -s "$BACKUP_DIR/database.sql" ]]; then
        error "Database backup is empty. Migration will not continue."
        return 1
    fi

    chmod 600 "$BACKUP_DIR/database.sql"

    echo "$BACKUP_DIR" > "$BACKUP_ROOT/LATEST"
    chmod 600 "$BACKUP_ROOT/LATEST"

    success "Backup completed."
    echo -e "${WHITE}Backup directory:${RESET} $BACKUP_DIR"
}

# ---------- RESTORE DATABASE ----------
restore_database_dump() {
    local sql_file="$1"

    if [[ ! -s "$sql_file" ]]; then
        error "Database backup is missing or empty: $sql_file"
        return 1
    fi

    msg "Restoring database: $DB_DATABASE"

    if ! MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_USERNAME" \
        "$DB_DATABASE" < "$sql_file"; then
        error "Database restoration failed."
        return 1
    fi

    success "Database restoration command completed."
}

# ---------- AUTOMATIC RECOVERY ON INSTALL ERROR ----------
automatic_recovery() {
    trap - ERR
    set +e

    echo
    error "An installation command failed."

    if [[ "$INSTALL_IN_PROGRESS" -eq 1 ]]; then
        warn "Attempting to restore the pre-installation backup..."

        if [[ -f "$BACKUP_DIR/panel-files.tar.gz" ]]; then
            rm -rf -- "$PANEL_DIR"

            tar -xzpf "$BACKUP_DIR/panel-files.tar.gz" \
                -C "$(dirname "$PANEL_DIR")"

            if [[ -f "$BACKUP_DIR/database.sql" ]]; then
                restore_database_dump "$BACKUP_DIR/database.sql"
            fi

            success "Panel files have been restored from backup."
            warn "Review the database restoration result above."
        else
            error "The panel file backup was not found."
            error "Manual recovery may be necessary."
        fi
    else
        warn "The panel replacement had not started."
        warn "Your existing panel files were not intentionally replaced."
    fi

    echo
    error "Installation did not finish successfully."
    echo "Keep this backup for troubleshooting: $BACKUP_DIR"
    exit 1
}

# ---------- INSTALL / MIGRATE ----------
install_reviactyl() {
    banner

    echo -e "${YELLOW}IMPORTANT: THIS REPLACES THE PANEL APPLICATION CODE.${RESET}"
    echo "It is not a simple CSS/theme-only installer."
    echo "Your existing database and configuration must be compatible."
    echo

    if ! ask_panel_path; then
        pause_screen
        return
    fi

    if ! check_php_version; then
        pause_screen
        return
    fi

    if ! command -v composer >/dev/null 2>&1; then
        error "Composer is not installed."
        echo "Install Composer before running this migration."
        pause_screen
        return
    fi

    if ! read_database_settings "$PANEL_DIR/.env"; then
        pause_screen
        return
    fi

    # Keep the existing application key. Never generate a new key here.
    if ! grep -Eq '^APP_KEY=.+$' "$PANEL_DIR/.env"; then
        error "APP_KEY is missing or empty in .env."
        error "Fix the key before proceeding. Do not generate a new key blindly."
        pause_screen
        return
    fi

    TMP_DIR="$(mktemp -d /tmp/ryn-reviactyl.XXXXXXXX)"
    trap 'rm -rf "${TMP_DIR:-}"' EXIT

    msg "Downloading the official Reviactyl release..."
    if ! curl -fL --retry 3 --connect-timeout 20 \
        "$RELEASE_URL" -o "$TMP_DIR/panel.tar.gz"; then
        error "Download failed."
        pause_screen
        return
    fi

    if ! tar -tzf "$TMP_DIR/panel.tar.gz" >/dev/null 2>&1; then
        error "Downloaded release is not a valid tar.gz archive."
        pause_screen
        return
    fi

    mkdir -p "$TMP_DIR/new-panel"

    if ! tar -xzf "$TMP_DIR/panel.tar.gz" -C "$TMP_DIR/new-panel"; then
        error "Could not extract Reviactyl."
        pause_screen
        return
    fi

    if [[ ! -f "$TMP_DIR/new-panel/artisan" ||
          ! -f "$TMP_DIR/new-panel/composer.json" ||
          ! -d "$TMP_DIR/new-panel/public" ]]; then
        error "Release archive did not contain the expected panel files."
        pause_screen
        return
    fi

    echo
    echo -e "${YELLOW}Before continuing, confirm the following:${RESET}"
    echo "  1. You want to replace the panel code with Reviactyl."
    echo "  2. The existing database and APP_KEY must be preserved."
    echo "  3. A file archive and database dump will be created."
    echo "  4. A migration may still fail if your installation is incompatible."
    echo
    read -r -p "Type MIGRATE to continue: " confirmation

    if [[ "$confirmation" != "MIGRATE" ]]; then
        warn "Cancelled. No panel replacement was performed."
        pause_screen
        return
    fi

    # Make backups before changing the current application.
    if ! create_backup; then
        error "Backup failed. Migration cancelled."
        pause_screen
        return
    fi

    OLD_DIR="${PANEL_DIR}.pre-reviactyl.$(date +%Y%m%d_%H%M%S)"

    # Preserve the original environment configuration and key.
    cp -a "$PANEL_DIR/.env" "$TMP_DIR/new-panel/.env"

    # Preserve existing storage data.
    if [[ -d "$PANEL_DIR/storage" ]]; then
        rm -rf "$TMP_DIR/new-panel/storage"
        cp -a "$PANEL_DIR/storage" "$TMP_DIR/new-panel/storage"
    fi

    # Preserve extensions when present.
    if [[ -d "$PANEL_DIR/extensions" ]]; then
        rm -rf "$TMP_DIR/new-panel/extensions"
        cp -a "$PANEL_DIR/extensions" "$TMP_DIR/new-panel/extensions"
    fi

    # Keep uploaded files if a public/uploads directory exists.
    # The new release's frontend assets are otherwise retained.
    if [[ -d "$PANEL_DIR/public/uploads" ]]; then
        mkdir -p "$TMP_DIR/new-panel/public/uploads"
        cp -a "$PANEL_DIR/public/uploads/." \
            "$TMP_DIR/new-panel/public/uploads/"
    fi

    # Activate automatic recovery before moving the live panel.
    INSTALL_IN_PROGRESS=1
    trap automatic_recovery ERR

    msg "Switching to the new Reviactyl application files..."

    mv "$PANEL_DIR" "$OLD_DIR"
    mv "$TMP_DIR/new-panel" "$PANEL_DIR"

    msg "Setting application permissions..."

    WEB_USER="www-data"
    WEB_GROUP="www-data"

    if id nginx >/dev/null 2>&1 && ! id www-data >/dev/null 2>&1; then
        WEB_USER="nginx"
        WEB_GROUP="nginx"
    elif id apache >/dev/null 2>&1 && ! id www-data >/dev/null 2>&1; then
        WEB_USER="apache"
        WEB_GROUP="apache"
    fi

    chown -R "$WEB_USER:$WEB_GROUP" "$PANEL_DIR"

    mkdir -p "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    chown -R "$WEB_USER:$WEB_GROUP" \
        "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

    chmod -R ug+rwX \
        "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

    msg "Installing PHP dependencies..."

    (
        cd "$PANEL_DIR"
        COMPOSER_ALLOW_SUPERUSER=1 composer install \
            --no-dev \
            --optimize-autoloader \
            --no-interaction
    )

    msg "Clearing Laravel caches..."

    (
        cd "$PANEL_DIR"
        php artisan optimize:clear
    )

    msg "Running database migrations..."

    (
        cd "$PANEL_DIR"
        php artisan migrate --seed --force
    )

    msg "Restarting application queue workers..."

    (
        cd "$PANEL_DIR"
        php artisan queue:restart
    ) || warn "Queue restart failed. Check the queue worker configuration."

    # Reapply permissions after Composer and Laravel commands.
    chown -R "$WEB_USER:$WEB_GROUP" "$PANEL_DIR"
    chmod -R ug+rwX \
        "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

    systemctl reload nginx 2>/dev/null || true

    # Reload PHP-FPM if an active service can be identified.
    while read -r service_name; do
        [[ -n "$service_name" ]] || continue
        systemctl reload "$service_name" 2>/dev/null || true
    done < <(
        systemctl list-units --type=service --state=running \
            --no-legend 'php*-fpm.service' 2>/dev/null |
            awk '{print $1}'
    )

    INSTALL_IN_PROGRESS=0
    trap - ERR

    # The full archive now serves as the rollback copy.
    rm -rf -- "$OLD_DIR"

    success "Reviactyl installation completed."
    echo
    echo -e "${WHITE}Panel directory:${RESET} $PANEL_DIR"
    echo -e "${WHITE}Domain:${RESET} $DEFAULT_DOMAIN"
    echo -e "${WHITE}Backup:${RESET} $BACKUP_DIR"
    echo
    warn "Check the panel in your browser and test login and server management."
    warn "Do not delete the backup until everything has been verified."
    pause_screen
}

# ---------- FIND LATEST BACKUP FOR A PANEL ----------
find_latest_backup() {
    local wanted_path="$1"
    local candidate stored_path
    local latest=""

    shopt -s nullglob

    for candidate in "$BACKUP_ROOT"/*; do
        [[ -d "$candidate" ]] || continue
        [[ -f "$candidate/panel_path.txt" ]] || continue
        [[ -f "$candidate/panel-files.tar.gz" ]] || continue
        [[ -f "$candidate/database.sql" ]] || continue

        stored_path="$(cat "$candidate/panel_path.txt")"

        if [[ "$stored_path" == "$wanted_path" ]]; then
            if [[ -z "$latest" || "$candidate" > "$latest" ]]; then
                latest="$candidate"
            fi
        fi
    done

    shopt -u nullglob
    printf '%s' "$latest"
}

# ---------- RESTORE / UNDO MIGRATION ----------
restore_previous_panel() {
    banner

    echo -e "${YELLOW}RESTORE PREVIOUS PANEL${RESET}"
    echo "This restores the panel files and imports the saved database dump."
    echo "The database import can replace tables using the same names."
    echo

    if ! ask_panel_path; then
        pause_screen
        return
    fi

    if [[ ! -d "$BACKUP_ROOT" ]]; then
        error "No backup directory found: $BACKUP_ROOT"
        pause_screen
        return
    fi

    local selected_backup
    selected_backup="$(find_latest_backup "$PANEL_DIR")"

    if [[ -z "$selected_backup" ]]; then
        error "No complete backup was found for $PANEL_DIR."
        pause_screen
        return
    fi

    echo
    echo -e "${WHITE}Backup to restore:${RESET} $selected_backup"
    echo
    warn "Restoring will replace the current panel files."
    warn "The SQL dump may replace database tables created or changed since backup."
    echo
    read -r -p "Type RESTORE to continue: " confirmation

    if [[ "$confirmation" != "RESTORE" ]]; then
        warn "Restore cancelled."
        pause_screen
        return
    fi

    TMP_DIR="$(mktemp -d /tmp/ryn-restore.XXXXXXXX)"
    trap 'rm -rf "${TMP_DIR:-}"' EXIT

    local archived_env
    archived_env="$TMP_DIR/backup.env"

    if ! tar -xOf "$selected_backup/panel-files.tar.gz" \
        "$(basename "$PANEL_DIR")/.env" > "$archived_env"; then
        error "Could not read the saved .env file from the backup."
        pause_screen
        return
    fi

    if ! read_database_settings "$archived_env"; then
        pause_screen
        return
    fi

    msg "Restoring panel files..."

    rm -rf -- "$PANEL_DIR"

    if ! tar -xzpf "$selected_backup/panel-files.tar.gz" \
        -C "$(dirname "$PANEL_DIR")"; then
        error "Restoring the panel files failed."
        pause_screen
        return
    fi

    msg "Restoring the database dump..."

    if ! restore_database_dump "$selected_backup/database.sql"; then
        error "Panel files were restored, but database restoration failed."
        error "Check database permissions and the MySQL/MariaDB service."
        pause_screen
        return
    fi

    success "Previous panel files and database dump have been restored."
    echo
    echo "Restored from: $selected_backup"
    warn "Check the panel and its services before deleting any backups."
    pause_screen
}

# ---------- MAIN MENU ----------
main_menu() {
    check_root
    check_tools

    while true; do
        banner

        echo -e "${GREEN}Domain:${RESET}  $DEFAULT_DOMAIN"
        echo -e "${GREEN}Default:${RESET} $DEFAULT_PANEL_DIR"
        echo
        echo -e "${RED}[1]${RESET} Install / Migrate to Reviactyl"
        echo -e "${RED}[2]${RESET} Restore previous panel from backup"
        echo -e "${RED}[3]${RESET} Exit"
        echo

        read -r -p "Select an option [1-3]: " option

        case "$option" in
            1)
                install_reviactyl
                ;;
            2)
                restore_previous_panel
                ;;
            3)
                echo -e "${GREEN}Goodbye!${RESET}"
                exit 0
                ;;
            *)
                error "Invalid option. Select 1, 2, or 3."
                sleep 1
                ;;
        esac
    done
}

main_menu

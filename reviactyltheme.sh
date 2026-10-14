#!/bin/bash
# ============================================================
# REVI ACTYL PANEL INSTALLER & MANAGER
# Made by TheRynzo
# Ubuntu 24.04 | PHP 8.3+ | Nginx | MariaDB | Redis
# ============================================================

set -Eeuo pipefail
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
BACKUP_DIR="/root/reviactyl-backups"
DOMAIN="${PANEL_DOMAIN:-gp.aliennode.in}"
RELEASE_URL="https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz"

RESET=$'\033[0m'
WHITE=$'\033[1;37m'
RED=$'\033[38;2;255;70;70m'
GREEN=$'\033[38;2;80;255;130m'
YELLOW=$'\033[38;2;255;210;80m'
BLUE=$'\033[38;2;100;180;255m'

# ------------------------------------------------------------
# ERROR HANDLING
# ------------------------------------------------------------

on_error() {
    local code=$?
    echo
    printf '%s[ERROR]%s Script failed at line %s (exit code %s).\n' \
        "$RED" "$RESET" "${BASH_LINENO[0]:-unknown}" "$code"
    echo "If migration failed, preserve the backups in $BACKUP_DIR."
    echo "Do not delete your database or generate a new APP_KEY."
    exit "$code"
}
trap on_error ERR

# ------------------------------------------------------------
# BANNER
# Light red at the top, dark red at the bottom
# ------------------------------------------------------------

banner() {
    clear 2>/dev/null || true

    printf '\033[38;2;255;170;170m'
    printf ' _____ _   _ _____ ____  _____ _   _ _____ ___\n'

    printf '\033[38;2;255;115;115m'
    printf '|_   _| | | | ____|  _ \\|_   _| | | |_   _/ _ \\\n'

    printf '\033[38;2;230;55;55m'
    printf '  | | | |_| |  _| | |_) | | | | |_| | | || | | |\n'

    printf '\033[38;2;185;25;25m'
    printf '  | | |  _  | |___|  _ <  | | |  _  | | || |_| |\n'

    printf '\033[38;2;120;0;0m'
    printf '  |_| |_| |_|_____|_| \\_\\ |_| |_| |_| |_| \\___/\n'

    printf '%s\n' "$RESET"
    printf '%s       REVI ACTYL PANEL MANAGER%s\n' "$WHITE" "$RESET"
    printf '%s          Made by TheRynzo%s\n' "$RED" "$RESET"
    printf '%s========================================%s\n' "$RED" "$RESET"
    printf '%s Domain: %s%s\n' "$BLUE" "$DOMAIN" "$RESET"
    printf '%s Panel:  %s%s\n\n' "$BLUE" "$PANEL_DIR" "$RESET"
}

# ------------------------------------------------------------
# ROOT AND OPERATING SYSTEM CHECKS
# ------------------------------------------------------------

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Please run this script as root."
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo "Cannot identify the operating system."
        return 1
    fi

    . /etc/os-release

    case "${ID:-}" in
        ubuntu|debian)
            echo "Detected operating system: ${PRETTY_NAME:-$ID}"
            ;;
        *)
            echo "This script supports Ubuntu and Debian."
            echo "Detected: ${PRETTY_NAME:-unknown}"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# ENVIRONMENT FILE READER
# Uses Laravel's installed Dotenv parser.
# Values are never printed.
# ------------------------------------------------------------

env_value() {
    local key="$1"

    PANEL_ROOT="$PANEL_DIR" ENV_KEY="$key" php -r '
        require getenv("PANEL_ROOT") . "/vendor/autoload.php";
        $file = getenv("PANEL_ROOT") . "/.env";
        $data = \Dotenv\Dotenv::parse(file_get_contents($file));
        echo $data[getenv("ENV_KEY")] ?? "";
    '
}

# ------------------------------------------------------------
# VALIDATE EXISTING PANEL
# ------------------------------------------------------------

check_panel() {
    if [[ ! -f "$PANEL_DIR/artisan" ||
          ! -f "$PANEL_DIR/composer.json" ||
          ! -f "$PANEL_DIR/.env" ||
          ! -f "$PANEL_DIR/vendor/autoload.php" ]]; then
        echo "An existing, initialized panel was not found."
        echo "Expected location: $PANEL_DIR"
        echo "This menu option migrates an existing panel."
        return 1
    fi

    if ! grep -q '^APP_KEY=base64:.\{20,\}' "$PANEL_DIR/.env"; then
        echo "ERROR: APP_KEY is missing or invalid."
        echo "Restore the original key before continuing."
        return 1
    fi
}

# ------------------------------------------------------------
# BACKUP FILES AND DATABASE
# ------------------------------------------------------------

backup_panel() {
    local stamp app_backup db_backup env_backup
    local db_name db_user db_password db_host db_port

    echo
    printf '%s[BACKUP] Starting backup...%s\n' "$YELLOW" "$RESET"

    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    stamp="$(date +%Y%m%d-%H%M%S)"

    app_backup="$BACKUP_DIR/panel-files-$stamp.tar.gz"
    db_backup="$BACKUP_DIR/panel-database-$stamp.sql"
    env_backup="$BACKUP_DIR/panel-env-$stamp.env"

    # Preserve application files, including the existing APP_KEY.
    tar -czf "$app_backup" \
        -C "$(dirname "$PANEL_DIR")" "$(basename "$PANEL_DIR")"

    cp -a "$PANEL_DIR/.env" "$env_backup"
    chmod 600 "$app_backup" "$env_backup"

    # Read the database connection from .env without printing secrets.
    db_name="$(env_value DB_DATABASE)"
    db_user="$(env_value DB_USERNAME)"
    db_password="$(env_value DB_PASSWORD)"
    db_host="$(env_value DB_HOST)"
    db_port="$(env_value DB_PORT)"

    db_host="${db_host:-127.0.0.1}"
    db_port="${db_port:-3306}"

    if [[ -z "$db_name" ]]; then
        echo "ERROR: DB_DATABASE is empty."
        return 1
    fi

    echo "Backing up database: $db_name"

    if ! MYSQL_PWD="$db_password" mariadb-dump \
        --host="$db_host" \
        --port="$db_port" \
        --user="${db_user:-root}" \
        --single-transaction \
        --quick \
        --skip-lock-tables \
        "$db_name" > "$db_backup"; then

        echo "Database credentials failed; trying local root access."

        if ! mariadb-dump \
            --single-transaction \
            --quick \
            --skip-lock-tables \
            "$db_name" > "$db_backup"; then
            rm -f "$db_backup"
            echo "ERROR: Database backup failed. Aborting."
            return 1
        fi
    fi

    if [[ ! -s "$db_backup" ]]; then
        echo "ERROR: The database backup is empty."
        return 1
    fi

    chmod 600 "$db_backup"

    printf '%s[OK]%s Backups created successfully.\n' "$GREEN" "$RESET"
    echo "Application: $app_backup"
    echo "Database:    $db_backup"
    echo "Environment: $env_backup"
}

# ------------------------------------------------------------
# INSTALL DEPENDENCIES
# Uses the current PHP CLI version.
# ------------------------------------------------------------

install_dependencies() {
    local php_version

    echo
    printf '%s[1/6] Installing dependencies...%s\n' "$BLUE" "$RESET"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    php_version="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"

    if [[ -z "$php_version" ]]; then
        echo "PHP is not installed. Install PHP 8.3 or newer first."
        return 1
    fi

    if [[ "$(printf '%s\n' 8.3 "$php_version" | sort -V | head -n1)" != "8.3" ]]; then
        echo "PHP 8.3 or newer is required. Detected: $php_version"
        return 1
    fi

    apt-get install -y \
        curl ca-certificates tar unzip git \
        nginx mariadb-server redis-server \
        "php${php_version}-cli" \
        "php${php_version}-common" \
        "php${php_version}-gd" \
        "php${php_version}-mysql" \
        "php${php_version}-mbstring" \
        "php${php_version}-bcmath" \
        "php${php_version}-xml" \
        "php${php_version}-fpm" \
        "php${php_version}-curl" \
        "php${php_version}-zip" \
        "php${php_version}-intl" \
        "php${php_version}-redis" \
        "php${php_version}-sqlite3"

    if ! command -v composer >/dev/null 2>&1; then
        echo "Installing Composer..."

        curl -fsSL https://getcomposer.org/installer \
            -o /tmp/composer-installer.php

        php /tmp/composer-installer.php \
            --2 \
            --install-dir=/usr/local/bin \
            --filename=composer

        rm -f /tmp/composer-installer.php
    fi

    composer --version

    echo "Dependencies installed."
}

# ------------------------------------------------------------
# INSTALL / MIGRATE REVI ACTYL
# ------------------------------------------------------------

install_reviactyl() {
    local confirmation workdir archive php_version maria_version maria_major

    check_panel
    check_os

    echo
    printf '%sWARNING: EXISTING PANEL MIGRATION%s\n' "$YELLOW" "$RESET"
    echo "Target: $PANEL_DIR"
    echo "Release: $RELEASE_URL"
    echo
    echo "This will replace the application code with Reviactyl."
    echo "The script preserves .env, storage, public, extensions and database."
    echo "A new application key will NOT be generated."
    echo

    read -r -p 'Type MIGRATE to continue: ' confirmation

    if [[ "$confirmation" != "MIGRATE" ]]; then
        echo "Migration cancelled."
        return 0
    fi

    # Backup must complete before any migration changes.
    backup_panel

    install_dependencies

    # Current Reviactyl documentation recommends MariaDB 11 or newer.
    maria_version="$(mariadb --version 2>/dev/null || true)"

    if [[ "$maria_version" =~ Distrib[[:space:]]([0-9]+)\. ]]; then
        maria_major="${BASH_REMATCH[1]}"

        if (( maria_major < 11 )); then
            echo
            printf '%sWARNING: DATABASE VERSION%s\n' "$YELLOW" "$RESET"
            echo "$maria_version"
            echo "The documentation you supplied specifies MariaDB 11 or newer."
            echo "This script will not automatically upgrade or replace your database."

            read -r -p 'Type CONTINUE to proceed with this version: ' confirmation

            if [[ "$confirmation" != "CONTINUE" ]]; then
                echo "Migration cancelled. Backups are preserved."
                return 0
            fi
        fi
    fi

    workdir="$(mktemp -d /tmp/reviactyl.XXXXXX)"
    archive="$workdir/panel.tar.gz"

    echo
    printf '%s[2/6] Downloading Reviactyl release...%s\n' "$BLUE" "$RESET"

    curl -fL --retry 3 --retry-delay 2 \
        "$RELEASE_URL" -o "$archive"

    tar -tzf "$archive" >/dev/null

    if ! tar -tzf "$archive" | grep -qx 'artisan'; then
        rm -rf "$workdir"
        echo "ERROR: The release archive does not contain artisan at its root."
        return 1
    fi

    echo
    printf '%s[3/6] Replacing application files...%s\n' "$BLUE" "$RESET"

    # Follow the supplied Reviactyl migration instructions:
    # preserve environment, storage, public assets and extensions.
    find "$PANEL_DIR" \
        -mindepth 1 -maxdepth 1 \
        ! -name '.env' \
        ! -name 'storage' \
        ! -name 'public' \
        ! -name 'extensions' \
        ! -name 'database' \
        -exec rm -rf -- {} +

    tar -xzf "$archive" -C "$PANEL_DIR"

    rm -rf "$workdir"

    cd "$PANEL_DIR"

    echo
    printf '%s[4/6] Installing Composer dependencies...%s\n' "$BLUE" "$RESET"

    COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

    echo
    printf '%s[5/6] Running database migrations...%s\n' "$BLUE" "$RESET"

    # Do not reset or drop the database.
    # Do not replace the existing encryption key.
    php artisan migrate --seed --force
    php artisan optimize:clear

    echo
    printf '%s[6/6] Fixing permissions and restarting services...%s\n' "$BLUE" "$RESET"

    php_version="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

    install -d \
        -o www-data -g www-data -m 775 \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/storage/logs" \
        "$PANEL_DIR/bootstrap/cache"

    chown -R www-data:www-data \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/bootstrap/cache"

    chmod -R 775 \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/bootstrap/cache"

    # Keep the environment file protected.
    chown root:www-data "$PANEL_DIR/.env"
    chmod 640 "$PANEL_DIR/.env"

    systemctl enable --now mariadb redis-server "php${php_version}-fpm"

    nginx -t
    systemctl restart "php${php_version}-fpm" nginx

    if systemctl cat pteroq.service >/dev/null 2>&1; then
        systemctl restart pteroq.service || true
    fi

    if systemctl cat reviq.service >/dev/null 2>&1; then
        systemctl restart reviq.service || true
    fi

    echo
    printf '%sMIGRATION COMMANDS COMPLETED%s\n' "$GREEN" "$RESET"
    echo "Panel directory: $PANEL_DIR"
    echo "Backup directory: $BACKUP_DIR"
    echo

    echo "Testing local HTTPS..."

    curl -k -sS --max-time 15 \
        --resolve "$DOMAIN:443:127.0.0.1" \
        -o /dev/null \
        -w 'Local HTTPS status: %{http_code}\n' \
        "https://$DOMAIN/" || true

    echo
    echo "If no administrator account exists, run:"
    echo "cd $PANEL_DIR && php artisan p:user:make"
    echo
    echo "Cloudflare tunnel routing is not modified by this migration."
}

# ------------------------------------------------------------
# UNINSTALL
# Back up first, then move application directory.
# The database is NOT deleted.
# ------------------------------------------------------------

uninstall_reviactyl() {
    local confirmation destination stamp

    check_panel

    echo
    printf '%sWARNING: UNINSTALL APPLICATION%s\n' "$RED" "$RESET"
    echo "The panel application directory will be moved."
    echo "The database will NOT be deleted."
    echo "Nginx and Cloudflare settings will NOT be deleted."
    echo "The website will be unavailable until restored or reconfigured."
    echo

    read -r -p 'Type BACKUP-AND-UNINSTALL to continue: ' confirmation

    if [[ "$confirmation" != "BACKUP-AND-UNINSTALL" ]]; then
        echo "Uninstall cancelled."
        return 0
    fi

    backup_panel

    stamp="$(date +%Y%m%d-%H%M%S)"
    destination="${PANEL_DIR}.disabled-${stamp}"

    mv -- "$PANEL_DIR" "$destination"

    echo
    printf '%s[OK]%s Application directory moved to:\n' "$GREEN" "$RESET"
    echo "$destination"
    echo
    echo "Database preserved."
    echo "Backups preserved in: $BACKUP_DIR"
    echo "Nginx still needs reconfiguration if you want to serve another application."
}

# ------------------------------------------------------------
# MAIN MENU
# ------------------------------------------------------------

main_menu() {
    local option

    while true; do
        banner

        printf '%s[1]%s Install / Migrate to Reviactyl\n' "$RED" "$RESET"
        printf '%s[2]%s Uninstall application (backup first)\n' "$RED" "$RESET"
        printf '%s[3]%s Exit\n\n' "$RED" "$RESET"

        read -r -p 'Select an option [1-3]: ' option

        case "$option" in
            1)
                install_reviactyl
                read -r -p $'\nPress Enter to return to the menu...' _
                ;;
            2)
                uninstall_reviactyl
                read -r -p $'\nPress Enter to return to the menu...' _
                ;;
            3)
                echo "Goodbye! — TheRynzo"
                exit 0
                ;;
            *)
                printf '%sInvalid option. Select 1, 2 or 3.%s\n' "$RED" "$RESET"
                sleep 1
                ;;
        esac
    done
}

require_root
main_menu

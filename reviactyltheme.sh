#!/usr/bin/env bash
# Reviactyl migration installer / safe uninstaller
# Made by TheRynzo
# Intended for Debian/Ubuntu systems with an existing Pterodactyl/Reviactyl panel.

set -Eeuo pipefail
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
BACKUP_DIR="${BACKUP_DIR:-/root/reviactyl-backups}"
RELEASE_URL="https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz"

RED=$'\033[0;31m'
LIGHT_RED=$'\033[1;31m'
WHITE=$'\033[1;37m'
GRAY=$'\033[0;90m'
RESET=$'\033[0m'

pause() { read -r -p $'\nPress Enter to return to the menu...' _; }

banner() {
    clear 2>/dev/null || true
    local lines=(
' _____ _   _ _____ ____  _____ _   _ _____ ___  '
'|_   _| | | | ____|  _ \\|_   _| | | |_   _/ _ \\ '
'  | | | |_| |  _| | |_) | | | | |_| | | || | | |'
'  | | |  _  | |___|  _ <  | | |  _  | | || |_| |'
'  |_| |_| |_|_____|_| \\_\\ |_| |_| |_| |_| \\___/'
    )
    local colors=(255 217 196 160 124)
    local i
    printf '\n'
    for i in "${!lines[@]}"; do
        # Gradient runs from light red at the top to dark red at the bottom.
        case "$i" in
            0) printf '\033[38;2;255;150;150m%s\033[0m\n' "${lines[$i]}" ;;
            1) printf '\033[38;2;255;105;105m%s\033[0m\n' "${lines[$i]}" ;;
            2) printf '\033[38;2;230;55;55m%s\033[0m\n' "${lines[$i]}" ;;
            3) printf '\033[38;2;190;20;20m%s\033[0m\n' "${lines[$i]}" ;;
            *) printf '\033[38;2;125;0;0m%s\033[0m\n' "${lines[$i]}" ;;
        esac
    done
    printf '\n  %sREVI ACTYL PANEL MANAGER%s\n' "$WHITE" "$RESET"
    printf '  %sMade by TheRynzo | Backup-first installer%s\n\n' "$LIGHT_RED" "$RESET"
}

need_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf '%sRun this script as root: sudo bash %s%s\n' "$RED" "$0" "$RESET" >&2
        exit 1
    fi
}

read_env_value() {
    local key="$1" line value
    line="$(grep -m1 -E "^${key}=" "$PANEL_DIR/.env" 2>/dev/null || true)"
    [[ -n "$line" ]] || { printf ''; return; }
    value="${line#*=}"
    value="${value%$'\r'}"
    # Remove one pair of surrounding quotes; credentials containing quotes should be quoted in .env.
    if [[ "$value" == \\\"*\\\" ]]; then value="${value:1:${#value}-2}"; fi
    if [[ "$value" == \'*\' ]]; then value="${value:1:${#value}-2}"; fi
    printf '%s' "$value"
}

check_os() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
            ubuntu|debian) ;;
            *) printf '%sThis script is intended for Ubuntu/Debian. Detected: %s%s\n' "$RED" "${PRETTY_NAME:-unknown}" "$RESET"; return 1 ;;
        esac
    fi
}

install_dependencies() {
    printf '\n%s[1/6] Installing required PHP 8.3 and system packages...%s\n' "$LIGHT_RED" "$RESET"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        ca-certificates curl tar unzip git \
        nginx mariadb-server redis-server \
        php8.3-cli php8.3-common php8.3-gd php8.3-mysql php8.3-mbstring \
        php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip \
        php8.3-intl php8.3-redis php8.3-sqlite3

    if ! command -v composer >/dev/null 2>&1; then
        printf '%sComposer was not found. Installing Composer v2...%s\n' "$LIGHT_RED" "$RESET"
        curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
        php /tmp/composer-setup.php --2 --install-dir=/usr/local/bin --filename=composer
        rm -f /tmp/composer-setup.php
    fi
    command -v composer >/dev/null 2>&1 || { printf '%sERROR: Composer is still unavailable.%s\n' "$RED" "$RESET"; return 1; }
    php -r 'exit(PHP_VERSION_ID >= 80300 ? 0 : 1);' || {
        printf '%sERROR: Reviactyl v26 requires PHP 8.3 or later. Current CLI: %s%s\n' "$RED" "$(php -v | head -n1)" "$RESET"
        return 1
    }
}

backup_existing_panel() {
    local stamp db_name db_user db_pass db_host db_port db_connection app_backup db_backup env_backup
    stamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    app_backup="$BACKUP_DIR/panel-files-${stamp}.tar.gz"
    db_backup="$BACKUP_DIR/panel-database-${stamp}.sql"
    env_backup="$BACKUP_DIR/panel-env-${stamp}.env"

    printf '\n%s[BACKUP] Creating full panel-file backup...%s\n' "$LIGHT_RED" "$RESET"
    tar -czf "$app_backup" -C "$(dirname "$PANEL_DIR")" "$(basename "$PANEL_DIR")"
    [[ -s "$app_backup" ]] || { printf '%sERROR: Panel-file backup failed.%s\n' "$RED" "$RESET"; return 1; }
    cp -a "$PANEL_DIR/.env" "$env_backup"
    chmod 600 "$app_backup" "$env_backup"

    db_connection="$(read_env_value DB_CONNECTION)"
    db_name="$(read_env_value DB_DATABASE)"
    db_user="$(read_env_value DB_USERNAME)"
    db_pass="$(read_env_value DB_PASSWORD)"
    db_host="$(read_env_value DB_HOST)"
    db_port="$(read_env_value DB_PORT)"
    db_host="${db_host:-127.0.0.1}"
    db_port="${db_port:-3306}"

    case "${db_connection:-mysql}" in
        mysql|mariadb|"")
            [[ -n "$db_name" ]] || { printf '%sERROR: DB_DATABASE is empty in .env; cannot safely back up the database.%s\n' "$RED" "$RESET"; return 1; }
            printf '%s[BACKUP] Backing up database "%s"...%s\n' "$LIGHT_RED" "$db_name" "$RESET"
            if MYSQL_PWD="$db_pass" mariadb-dump --host="$db_host" --port="$db_port" --user="${db_user:-root}" --single-transaction --quick --skip-lock-tables "$db_name" > "$db_backup" 2>"$BACKUP_DIR/dump-error-${stamp}.log"; then
                :
            elif mariadb-dump --single-transaction --quick --skip-lock-tables "$db_name" > "$db_backup" 2>"$BACKUP_DIR/dump-error-${stamp}.log"; then
                :
            else
                rm -f "$db_backup"
                printf '%sERROR: Database backup failed. See %s/dump-error-%s.log. Nothing was migrated or uninstalled.%s\n' "$RED" "$BACKUP_DIR" "$stamp" "$RESET"
                return 1
            fi
            [[ -s "$db_backup" ]] || { printf '%sERROR: Database dump is empty; stopping.%s\n' "$RED" "$RESET"; return 1; }
            chmod 600 "$db_backup"
            ;;
        *)
            printf '%sERROR: This script currently backs up MySQL/MariaDB only. DB_CONNECTION=%s. No changes made.%s\n' "$RED" "$db_connection" "$RESET"
            return 1
            ;;
    esac

    printf '\n%sBackup completed:%s\n  Panel: %s\n  Database: %s\n  Environment: %s\n' "$WHITE" "$RESET" "$app_backup" "$db_backup" "$env_backup"
}

install_or_migrate() {
    local workdir archive answer maria_version
    if [[ ! -d "$PANEL_DIR" || ! -f "$PANEL_DIR/.env" || ! -f "$PANEL_DIR/artisan" ]]; then
        printf '%sExpected an existing Pterodactyl/Reviactyl panel with .env and artisan at %s.%s\n' "$RED" "$PANEL_DIR" "$RESET"
        printf 'This option is for migration, not a brand-new installation. Change PANEL_DIR before running if your panel is elsewhere.\n'
        return 1
    fi
    if ! grep -q '^APP_KEY=base64:.\{20,\}' "$PANEL_DIR/.env"; then
        printf '%sERROR: APP_KEY is missing/invalid. Stopping to avoid damaging encrypted data.%s\n' "$RED" "$RESET"
        return 1
    fi

    printf '\n%sWARNING:%s This will replace the application code at %s with the latest Reviactyl release.\n' "$LIGHT_RED" "$RESET" "$PANEL_DIR"
    printf 'It preserves .env, storage, extensions, public and database folders, and creates file + database backups first.\n'
    printf 'Your database will be migrated/seeds may update eggs; your app encryption key will NOT be regenerated.\n\n'
    read -r -p 'Type MIGRATE to continue: ' answer
    [[ "$answer" == "MIGRATE" ]] || { echo 'Cancelled.'; return 0; }

    check_os
    install_dependencies
    backup_existing_panel

    maria_version="$(mariadb --version 2>/dev/null || true)"
    if [[ "$maria_version" =~ 10\.([0-9]+) ]]; then
        printf '\n%sCompatibility warning:%s %s\nReviactyl documentation lists MariaDB 11 or newer. This VPS appears to use MariaDB 10.x. The script will NOT upgrade MariaDB automatically.\n' "$LIGHT_RED" "$RESET" "$maria_version"
        read -r -p 'Continue anyway? Type CONTINUE to proceed: ' answer
        [[ "$answer" == "CONTINUE" ]] || { echo 'Cancelled before replacing panel files. Backups were retained.'; return 0; }
    fi

    workdir="$(mktemp -d /tmp/reviactyl-install.XXXXXX)"
    archive="$workdir/panel.tar.gz"
    trap 'rm -rf "${workdir:-}"' RETURN
    printf '\n%s[2/6] Downloading the latest Reviactyl release...%s\n' "$LIGHT_RED" "$RESET"
    curl -fL --retry 3 --retry-delay 2 "$RELEASE_URL" -o "$archive"
    tar -tzf "$archive" >/dev/null
    tar -xzf "$archive" -C "$workdir"
    [[ -f "$workdir/artisan" && -f "$workdir/composer.json" ]] || { printf '%sERROR: Release archive does not contain artisan/composer.json; refusing to install.%s\n' "$RED" "$RESET"; return 1; }

    printf '%s[3/6] Replacing application code while preserving user data...%s\n' "$LIGHT_RED" "$RESET"
    # Match the official Reviactyl update/migration approach, after making full backups.
    find "$PANEL_DIR" -mindepth 1 -maxdepth 1 \
        ! -name 'public' ! -name '.env' ! -name 'extensions' \
        ! -name 'storage' ! -name 'database' -exec rm -rf -- {} +
    tar -xzf "$archive" -C "$PANEL_DIR"
    [[ -f "$PANEL_DIR/artisan" && -f "$PANEL_DIR/.env" ]] || {
        printf '%sERROR: Deployment verification failed. Restore the panel from the backup shown above before using it.%s\n' "$RED" "$RESET"
        return 1
    }

    printf '%s[4/6] Installing Composer dependencies...%s\n' "$LIGHT_RED" "$RESET"
    cd "$PANEL_DIR"
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

    printf '%s[5/6] Running database migrations and seeders...%s\n' "$LIGHT_RED" "$RESET"
    php artisan migrate --seed --force
    php artisan optimize:clear
    php artisan up || true

    printf '%s[6/6] Applying permissions and restarting services...%s\n' "$LIGHT_RED" "$RESET"
    chown -R www-data:www-data "$PANEL_DIR"
    chown root:www-data "$PANEL_DIR/.env"
    chmod 640 "$PANEL_DIR/.env"
    install -d -o www-data -g www-data -m 775 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" "$PANEL_DIR/storage/logs"
    chown -R www-data:www-data "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    chmod -R 775 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    nginx -t
    systemctl restart php8.3-fpm nginx mariadb redis-server
    if systemctl cat reviq.service >/dev/null 2>&1; then systemctl restart reviq.service || true; fi
    if systemctl cat pteroq.service >/dev/null 2>&1; then systemctl restart pteroq.service || true; fi
    if systemctl is-active --quiet cloudflared; then systemctl restart cloudflared || true; fi

    printf '\n%sMigration command sequence finished.%s\n' "$WHITE" "$RESET"
    printf 'Panel path: %s\nBackups: %s\n' "$PANEL_DIR" "$BACKUP_DIR"
    printf 'Local HTTPS test: '
    curl -ksS --max-time 12 -o /dev/null -w 'HTTP %{http_code}\n' --resolve "gp.aliennode.in:443:127.0.0.1" https://gp.aliennode.in/ || true
    printf '\nIf you need a new administrator, run: cd %q && php artisan p:user:make\n' "$PANEL_DIR"
    printf 'Note: this script does not configure/alter your Cloudflare dashboard routes or upgrade MariaDB automatically.\n'
}

uninstall_panel() {
    local answer stamp destination
    if [[ ! -d "$PANEL_DIR" || ! -f "$PANEL_DIR/.env" || ! -f "$PANEL_DIR/artisan" ]]; then
        printf '%sNo panel application found at %s.%s\n' "$LIGHT_RED" "$PANEL_DIR" "$RESET"
        return 1
    fi
    printf '\n%sUNINSTALL WARNING%s\n' "$RED" "$RESET"
    printf 'This removes the live application directory by renaming it. It does NOT delete the database, Nginx config, Cloudflare Tunnel, Redis, or panel backups.\n'
    printf 'The website will stop working at its current document root until you restore or reconfigure it.\n\n'
    read -r -p 'Type BACKUP-AND-UNINSTALL to continue: ' answer
    [[ "$answer" == 'BACKUP-AND-UNINSTALL' ]] || { echo 'Cancelled.'; return 0; }
    backup_existing_panel || return 1
    stamp="$(date +%Y%m%d-%H%M%S)"
    destination="${PANEL_DIR}.uninstalled-${stamp}"
    mv -- "$PANEL_DIR" "$destination"
    printf '\n%sApplication directory moved to:%s %s\n' "$WHITE" "$RESET" "$destination"
    printf 'Database and Nginx configuration were left untouched. Backups are in %s\n' "$BACKUP_DIR"
}

show_menu() {
    while true; do
        banner
        printf '  %s[1]%s Install / migrate existing panel to Reviactyl\n' "$LIGHT_RED" "$RESET"
        printf '  %s[2]%s Uninstall panel application (backup first; keeps database)\n' "$LIGHT_RED" "$RESET"
        printf '  %s[3]%s Exit\n\n' "$LIGHT_RED" "$RESET"
        read -r -p 'Select an option [1-3]: ' option
        case "$option" in
            1) install_or_migrate; pause ;;
            2) uninstall_panel; pause ;;
            3) printf '\n%sGoodbye! — TheRynzo%s\n' "$LIGHT_RED" "$RESET"; exit 0 ;;
            *) printf '%sInvalid option. Choose 1, 2, or 3.%s\n' "$RED" "$RESET"; sleep 1 ;;
        esac
    done
}

need_root
show_menu

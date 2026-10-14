#!/usr/bin/env bash
# =====================================================================
# TheRynzo Reviactyl Installer & Recovery
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
        return 1
    }
    if ! grep -Eq '^APP_KEY=base64:.{20,}$' "$PANEL_DIR/.env"; then
        fail 'APP_KEY is missing/invalid. Restore the original key before migrating; this script will not generate a new key.'
        return 1
    fi
}

# Read a key via Laravel's installed Dotenv parser. Values are not printed.
env_value() {
    local key="$1"
    PANEL_ROOT="$PANEL_DIR" ENV_KEY="$key" php -r '
        $root = getenv("PANEL_ROOT");
        require $root . "/vendor/autoload.php";
        $contents = file_get_contents($root . "/.env");
        $data = Dotenv\Dotenv::parse($contents);
        echo (string)($data[getenv("ENV_KEY")] ?? "");
    '
}

read_database_config() {
    DB_CONNECTION="$(env_value DB_CONNECTION)"
    DB_HOST="$(env_value DB_HOST)"
    DB_PORT="$(env_value DB_PORT)"
    DB_DATABASE="$(env_value DB_DATABASE)"
    DB_USERNAME="$(env_value DB_USERNAME)"
    DB_PASSWORD="$(env_value DB_PASSWORD)"
    DB_HOST="${DB_HOST:-127.0.0.1}"
    DB_PORT="${DB_PORT:-3306}"

    [[ "$DB_CONNECTION" == "mysql" || "$DB_CONNECTION" == "mariadb" ]] || {
        fail "Unsupported DB_CONNECTION='$DB_CONNECTION'; this script supports MySQL/MariaDB."; return 1;
    }
    [[ -n "$DB_DATABASE" && -n "$DB_USERNAME" ]] || {
        fail 'DB_DATABASE or DB_USERNAME is empty in .env.'; return 1;
    }
    MYSQL_BIN="$(command -v mariadb || command -v mysql || true)"
    DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump || true)"
    [[ -n "$MYSQL_BIN" && -n "$DUMP_BIN" ]] || {
        fail 'MySQL/MariaDB client and dump utility are required. Install mariadb-client first.'; return 1;
    }
}

get_panel_domain() {
    if [[ -z "$PANEL_DOMAIN" ]]; then
        local app_url
        app_url="$(env_value APP_URL 2>/dev/null || true)"
        PANEL_DOMAIN="$(APP_URL_VALUE="$app_url" php -r '$u=parse_url(getenv("APP_URL_VALUE")); echo $u["host"] ?? "localhost";')"
    fi
}

make_backup() {
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_ROOT"
    chmod 700 "$BACKUP_ROOT"
    BACKUP_DIR="$BACKUP_ROOT/$stamp"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    info 'Creating a full panel files backup...'
    tar -czpf "$BACKUP_DIR/panel-files.tar.gz" -C "$(dirname "$PANEL_DIR")" "$(basename "$PANEL_DIR")"
    tar -tzf "$BACKUP_DIR/panel-files.tar.gz" >/dev/null

    info "Backing up database '$DB_DATABASE'..."
    if ! MYSQL_PWD="$DB_PASSWORD" "$DUMP_BIN" \
        --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USERNAME" \
        --single-transaction --quick --routines --triggers --events --add-drop-table \
        "$DB_DATABASE" > "$BACKUP_DIR/database.sql"; then
        rm -f "$BACKUP_DIR/database.sql"
        fail 'Database backup failed. Stopping before modifying the panel.'
        return 1
    fi
    [[ -s "$BACKUP_DIR/database.sql" ]] || { fail 'Database backup is empty.'; return 1; }

    printf '%s\n' "$PANEL_DIR" > "$BACKUP_DIR/panel_path.txt"
    printf '%s\n' "$DB_DATABASE" > "$BACKUP_DIR/database_name.txt"
    chmod 600 "$BACKUP_DIR/panel-files.tar.gz" "$BACKUP_DIR/database.sql" "$BACKUP_DIR/panel_path.txt" "$BACKUP_DIR/database_name.txt"
    printf '%s\n' "$BACKUP_DIR" > "$BACKUP_ROOT/LATEST"
    chmod 600 "$BACKUP_ROOT/LATEST"
    ok "Backup completed: $BACKUP_DIR"
}

install_php_dependencies() {
    local v f packages
    local -a versions=()
    PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
    [[ -n "$PHP_VERSION" ]] || { fail 'PHP CLI is not installed.'; return 1; }
    if [[ "$(printf '%s\n' 8.3 "$PHP_VERSION" | sort -V | head -n1)" != '8.3' ]]; then
        fail "Reviactyl release requires PHP 8.3 or newer; CLI is $PHP_VERSION."; return 1
    fi

    versions+=("$PHP_VERSION")
    # Also install required extensions for PHP-FPM versions present on this host.
    for f in /etc/php/*/fpm/php.ini; do
        [[ -f "$f" ]] || continue
        v="$(printf '%s' "$f" | awk -F/ '{print $4}')"
        [[ "$v" =~ ^[0-9]+\.[0-9]+$ ]] && versions+=("$v")
    done
    mapfile -t versions < <(printf '%s\n' "${versions[@]}" | sort -Vu)

    export DEBIAN_FRONTEND=noninteractive
    info 'Installing required PHP extensions and system utilities...'
    apt-get update
    apt-get install -y curl ca-certificates tar gzip unzip git python3
    for v in "${versions[@]}"; do
        packages=("php${v}-cli" "php${v}-common" "php${v}-intl" "php${v}-bcmath" "php${v}-gd" "php${v}-mysql" "php${v}-mbstring" "php${v}-xml" "php${v}-curl" "php${v}-zip" "php${v}-redis")
        # FPM is installed only if that PHP version already has FPM configured or it is the CLI version.
        if [[ -f "/etc/php/$v/fpm/php.ini" || "$v" == "$PHP_VERSION" ]]; then packages+=("php${v}-fpm"); fi
        apt-get install -y "${packages[@]}"
    done

    local ext
    for ext in intl bcmath gd mysqli pdo_mysql mbstring xml curl zip; do
        if ! php -m | tr '[:upper:]' '[:lower:]' | grep -qx "$ext"; then
            fail "PHP extension '$ext' is still unavailable in PHP CLI ($PHP_VERSION)."; return 1
        fi
    done
    install_composer
}

install_composer() {
    local sig actual
    info 'Installing/verifying current Composer 2...'
    curl -fsSL --retry 3 https://composer.github.io/installer.sig -o /tmp/ryn-composer.sig
    curl -fsSL --retry 3 https://getcomposer.org/installer -o /tmp/ryn-composer-installer.php
    sig="$(tr -d '\r\n ' < /tmp/ryn-composer.sig)"
    actual="$(php -r 'echo hash_file("sha384", $argv[1]);' /tmp/ryn-composer-installer.php)"
    if [[ -z "$sig" || "$sig" != "$actual" ]]; then
        rm -f /tmp/ryn-composer.sig /tmp/ryn-composer-installer.php
        fail 'Composer installer signature check failed; refusing to install it.'
        return 1
    fi
    php /tmp/ryn-composer-installer.php --2 --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/ryn-composer.sig /tmp/ryn-composer-installer.php
    [[ -x /usr/local/bin/composer ]] || { fail 'Composer installation failed.'; return 1; }
    /usr/local/bin/composer --version
}

check_database_version() {
    local ver
    ver="$(MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USERNAME" "$DB_DATABASE" -Nse 'SELECT VERSION()' 2>/dev/null || true)"
    [[ -n "$ver" ]] || { warn 'Could not query the database server version; skipping version check.'; return 0; }
    if [[ "$ver" == *MariaDB* && "$ver" =~ ^([0-9]+)\.([0-9]+) ]]; then
        if (( BASH_REMATCH[1] < 11 )); then
            warn "Detected MariaDB server version: $ver"
            warn 'Reviactyl deployment guidance may require MariaDB 11+. This script will NOT upgrade/replace your database automatically.'
            read -r -p 'Type CONTINUE only if you have verified your database version is supported: ' answer
            [[ "$answer" == 'CONTINUE' ]] || { info 'Cancelled. Your existing panel files were not replaced.'; return 2; }
        fi
    fi
}

on_error() {
    local code="${1:-1}" line="${2:-unknown}"
    trap - ERR
    set +e
    echo
    fail "Command failed (exit $code, line $line)."
    # If live files were switched, restore the pre-migration files and backed-up tables.
    if [[ -n "$OLD_DIR" && -d "$OLD_DIR" ]]; then
        warn 'Rolling back the application files from the pre-migration directory...'
        if [[ -d "$PANEL_DIR" ]]; then
            mv "$PANEL_DIR" "${PANEL_DIR}.failed-$(date +%Y%m%d-%H%M%S)"
        fi
        mv "$OLD_DIR" "$PANEL_DIR"
        if [[ -n "$BACKUP_DIR" && -s "$BACKUP_DIR/database.sql" ]]; then
            warn 'Attempting to restore the database dump. Some newly-created tables may remain if the migration created them.'
            restore_database_dump "$BACKUP_DIR/database.sql" || fail 'Automatic database restore failed; use the saved SQL dump for manual recovery.'
        fi
        warn "Previous application files restored. Backup: $BACKUP_DIR"
    else
        warn 'Live application files had not been switched. The backup, if created, is preserved.'
    fi
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
    exit "$code"
}

restore_database_dump() {
    local sql="$1"
    [[ -s "$sql" ]] || { fail "Database dump missing/empty: $sql"; return 1; }
    MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USERNAME" "$DB_DATABASE" < "$sql"
}

install_reviactyl() {
    local answer archive stage dbcheck web_user web_group php_fpm
    choose_panel_dir || return 1
    check_panel || return 1
    check_os || return 1
    read_database_config || return 1
    get_panel_domain

    banner
    printf '%bWARNING: THIS IS A PANEL MIGRATION, NOT A CSS-ONLY THEME.%b\n' "$YELLOW" "$RESET"
    echo 'The existing panel application code will be replaced with Reviactyl.'
    echo 'The current .env / APP_KEY, storage data, existing public files, extensions and database are preserved/backed up.'
    echo 'The installer will install required PHP extensions, verify Composer, build dependencies in a staging directory, then switch the live panel.'
    echo
    read -r -p 'Type MIGRATE to continue: ' answer
    [[ "$answer" == 'MIGRATE' ]] || { info 'Cancelled; no panel files were changed.'; return 0; }

    make_backup
    install_php_dependencies
    dbcheck=0
    check_database_version || dbcheck=$?
    if (( dbcheck == 2 )); then return 0; elif (( dbcheck != 0 )); then return "$dbcheck"; fi

    WORK_DIR="$(mktemp -d "$(dirname "$PANEL_DIR")/.reviactyl-stage.XXXXXX")"
    archive="$WORK_DIR/panel.tar.gz"
    stage="$WORK_DIR/panel"

    info 'Downloading latest official Reviactyl release...'
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 "$RELEASE_URL" -o "$archive"
    tar -tzf "$archive" >/dev/null
    tar -tzf "$archive" | grep -qx 'artisan' || { fail 'Release archive does not contain artisan at its root.'; return 1; }
    mkdir -p "$stage"
    tar -xzf "$archive" -C "$stage"
    [[ -f "$stage/artisan" && -f "$stage/composer.json" && -f "$stage/composer.lock" && -d "$stage/public" ]] || {
        fail 'Release archive is missing required Laravel files.'; return 1;
    }

    info 'Preserving existing configuration and persistent directories in staging...'
    cp -a "$PANEL_DIR/.env" "$stage/.env"
    if [[ -d "$PANEL_DIR/storage" ]]; then rm -rf "$stage/storage"; cp -a "$PANEL_DIR/storage" "$stage/storage"; fi
    for dir in public extensions database; do
        if [[ -d "$PANEL_DIR/$dir" ]]; then
            mkdir -p "$stage/$dir"
            # Keep new release files where names conflict; copy only old extras/data.
            cp -an "$PANEL_DIR/$dir/." "$stage/$dir/"
        fi
    done

    info 'Installing Reviactyl dependencies in the staging directory...'
    (cd "$stage" && COMPOSER_ALLOW_SUPERUSER=1 /usr/local/bin/composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction)
    (cd "$stage" && COMPOSER_ALLOW_SUPERUSER=1 /usr/local/bin/composer check-platform-reqs --no-dev)
    (cd "$stage" && php artisan --version)

    OLD_DIR="${PANEL_DIR}.pre-reviactyl-$(date +%Y%m%d-%H%M%S)"
    info 'Activating the prepared release...'
    mv "$PANEL_DIR" "$OLD_DIR"
    mv "$stage" "$PANEL_DIR"

    web_user='www-data'; web_group='www-data'
    if ! id www-data >/dev/null 2>&1 && id nginx >/dev/null 2>&1; then web_user='nginx'; web_group='nginx'; fi
    install -d -o "$web_user" -g "$web_group" -m 775 "$PANEL_DIR/storage" "$PANEL_DIR/storage/logs" "$PANEL_DIR/bootstrap/cache"
    chown -R "$web_user:$web_group" "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    chmod -R ug+rwX "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    chown root:"$web_group" "$PANEL_DIR/.env"
    chmod 640 "$PANEL_DIR/.env"

    info 'Running Reviactyl database migrations...'
    (cd "$PANEL_DIR" && php artisan migrate --seed --force && php artisan optimize:clear && php artisan queue:restart)

    # Restart existing relevant services only; do not switch Nginx/FPM configuration automatically.
    php_fpm="php${PHP_VERSION}-fpm"
    if systemctl cat "$php_fpm.service" >/dev/null 2>&1; then systemctl restart "$php_fpm"; fi
    if systemctl cat nginx.service >/dev/null 2>&1; then nginx -t && systemctl reload nginx; fi
    if systemctl cat pteroq.service >/dev/null 2>&1; then systemctl restart pteroq.service || warn 'pteroq restart failed; check its service configuration.'; fi
    if systemctl cat reviq.service >/dev/null 2>&1; then systemctl restart reviq.service || warn 'reviq restart failed; check its service configuration.'; fi

    # Leave the pre-migration panel directory until the user verifies the site.
    ok 'Reviactyl migration commands completed.'
    echo "Panel:  $PANEL_DIR"
    echo "Domain: $PANEL_DOMAIN"
    echo "Backup: $BACKUP_DIR"
    echo "Old application folder: $OLD_DIR"
    echo
    warn 'Test sign-in, admin pages, server actions, queues and logs before deleting the old folder or backup.'
    echo 'If no admin account exists, check Reviactyl documentation before running any user-creation command.'
    rm -rf -- "$WORK_DIR"
    WORK_DIR=""
}

restore_latest_backup() {
    local answer target backup
    [[ -f "$BACKUP_ROOT/LATEST" ]] || { fail "No latest backup pointer found in $BACKUP_ROOT"; return 1; }
    backup="$(cat "$BACKUP_ROOT/LATEST")"
    [[ -d "$backup" && -s "$backup/panel-files.tar.gz" && -s "$backup/database.sql" && -f "$backup/panel_path.txt" ]] || {
        fail "Backup is incomplete: $backup"; return 1;
    }
    target="$(cat "$backup/panel_path.txt")"
    [[ "$target" == "$PANEL_DIR" ]] || {
        warn "This backup is for $target, not $PANEL_DIR. Set PANEL_DIR correctly or edit the path first."; return 1;
    }
    echo "This will replace $PANEL_DIR with the saved application files and restore the backed-up database tables."
    echo "Backup: $backup"
    read -r -p 'Type RESTORE to continue: ' answer
    [[ "$answer" == 'RESTORE' ]] || { info 'Restore cancelled.'; return 0; }

    # Read DB details before replacing any live files.
    check_panel || { warn 'Current panel validation failed; proceeding to restore files from the selected backup.'; }
    if [[ -f "$PANEL_DIR/.env" && -f "$PANEL_DIR/vendor/autoload.php" ]]; then
        read_database_config || return 1
    else
        fail 'Cannot read database credentials from the current panel. Restore the panel files manually and use the saved SQL file.'
        return 1
    fi

    local failed_dir="${PANEL_DIR}.before-restore-$(date +%Y%m%d-%H%M%S)"
    [[ ! -e "$PANEL_DIR" ]] || mv "$PANEL_DIR" "$failed_dir"
    tar -xzpf "$backup/panel-files.tar.gz" -C "$(dirname "$PANEL_DIR")"
    if restore_database_dump "$backup/database.sql"; then
        ok 'Panel files and backed-up database tables restored.'
        echo "The folder present before restore was kept at: $failed_dir"
    else
        fail 'Panel files were restored, but database restore failed. The SQL dump is preserved.'
        return 1
    fi
}

main() {
    local option
    require_root
    check_os
    while true; do
        banner
        printf '%b[1]%b Install / Migrate to Reviactyl (backup + dependency fixes)\n' "$RED" "$RESET"
        printf '%b[2]%b Restore latest backup\n' "$RED" "$RESET"
        printf '%b[3]%b Exit\n\n' "$RED" "$RESET"
        read -r -p 'Select an option [1-3]: ' option || exit 0
        case "$option" in
            1) install_reviactyl; pause_menu ;;
            2) restore_latest_backup; pause_menu ;;
            3) echo 'Goodbye! — TheRynzo'; exit 0 ;;
            *) warn 'Invalid option. Choose 1, 2 or 3.'; sleep 1 ;;
        esac
    done
}

trap 'on_error $? $LINENO' ERR
main "$@"

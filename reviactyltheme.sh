#!/usr/bin/env bash
# ============================================================
# TheRynzo Reviactyl Installer & Recovery
# Ubuntu/Debian | PHP 8.3+
# WARNING: Reviactyl replaces the panel; it is not CSS-only.
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
BACKUP_ROOT="${BACKUP_ROOT:-/root/reviactyl-backups}"
RELEASE_URL="https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz"

WORK_DIR=""
BACKUP_DIR=""
OLD_DIR=""
PHP_VERSION=""
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_DATABASE=""
DB_USERNAME=""
DB_PASSWORD=""
MYSQL_BIN=""
DUMP_BIN=""

RESET=$'\033[0m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[1;36m'
WHITE=$'\033[1;37m'

info() { printf '%b[INFO]%b %s\n' "$CYAN" "$RESET" "$*"; }
ok() { printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b[WARNING]%b %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$*" >&2; }

banner() {
    clear 2>/dev/null || true
    printf '%b' "$CYAN"
    cat <<'ART'
 _____ _   _ _____ ____  _____ _   _ _____ ___
|_   _| | | | ____|  _ \|_   _| | | |_   _/ _ \
  | | | |_| |  _| | |_) | | | | |_| | | || | | |
  | | |  _  | |___|  _ <  | | |  _  | | || |_| |
  |_| |_| |_|_____|_| \_\ |_| |_| |_| |_| \___/
ART
    printf '%b    REVIACTYL INSTALLER%b\n' "$WHITE" "$RESET"
    printf '%b           Made by TheRynzo%b\n' "$CYAN" "$RESET"
    printf '%bPanel: %s%b\n\n' "$WHITE" "$PANEL_DIR" "$RESET"
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        fail "Run this script as root."
        return 1
    fi
}

check_os() {
    [[ -r /etc/os-release ]] || {
        fail "Cannot identify the operating system."
        return 1
    }

    . /etc/os-release

    case "${ID:-}" in
        ubuntu|debian)
            info "Detected ${PRETTY_NAME:-$ID}"
            ;;
        *)
            fail "Only Ubuntu and Debian are supported."
            return 1
            ;;
    esac
}

check_panel() {
    [[ -d "$PANEL_DIR" && ! -L "$PANEL_DIR" ]] || {
        fail "Panel directory is missing or is a symlink: $PANEL_DIR"
        return 1
    }

    local f
    for f in artisan composer.json composer.lock .env vendor/autoload.php; do
        [[ -f "$PANEL_DIR/$f" ]] || {
            fail "Required file is missing: $PANEL_DIR/$f"
            return 1
        }
    done

    grep -Eq '^APP_KEY=base64:.{20,}$' "$PANEL_DIR/.env" || {
        fail "APP_KEY is missing or invalid. Refusing to generate a new key."
        return 1
    }
}

env_value() {
    local key="$1"

    PANEL_ROOT="$PANEL_DIR" ENV_KEY="$key" php -r '
        require getenv("PANEL_ROOT") . "/vendor/autoload.php";
        $env = Dotenv\Dotenv::parse(
            file_get_contents(getenv("PANEL_ROOT") . "/.env")
        );
        echo (string)($env[getenv("ENV_KEY")] ?? "");
    '
}

read_db_config() {
    local driver

    driver="$(env_value DB_CONNECTION)"

    [[ "$driver" == "mysql" || "$driver" == "mariadb" ]] || {
        fail "Unsupported database driver: $driver"
        return 1
    }

    DB_HOST="$(env_value DB_HOST)"
    DB_PORT="$(env_value DB_PORT)"
    DB_DATABASE="$(env_value DB_DATABASE)"
    DB_USERNAME="$(env_value DB_USERNAME)"
    DB_PASSWORD="$(env_value DB_PASSWORD)"

    DB_HOST="${DB_HOST:-127.0.0.1}"
    DB_PORT="${DB_PORT:-3306}"

    [[ -n "$DB_DATABASE" && -n "$DB_USERNAME" ]] || {
        fail "DB_DATABASE or DB_USERNAME is empty in .env."
        return 1
    }

    MYSQL_BIN="$(command -v mariadb || command -v mysql || true)"
    DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump || true)"

    if [[ -z "$MYSQL_BIN" || -z "$DUMP_BIN" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y mariadb-client

        MYSQL_BIN="$(command -v mariadb || command -v mysql || true)"
        DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump || true)"
    fi

    [[ -n "$MYSQL_BIN" && -n "$DUMP_BIN" ]] || {
        fail "MySQL/MariaDB client tools are unavailable."
        return 1
    }

    MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" \
        --host="$DB_HOST" --port="$DB_PORT" \
        --user="$DB_USERNAME" "$DB_DATABASE" \
        -Nse 'SELECT 1' >/dev/null || {
            fail "Cannot connect to the configured database. Stopping."
            return 1
        }
}

check_db_version() {
    local version major ans

    version="$(MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" \
        --host="$DB_HOST" --port="$DB_PORT" \
        --user="$DB_USERNAME" "$DB_DATABASE" \
        -Nse 'SELECT VERSION()' 2>/dev/null || true)"

    if [[ "$version" == *MariaDB* ]]; then
        major="${version%%.*}"

        if [[ "$major" =~ ^[0-9]+$ ]] && (( major < 11 )); then
            warn "Detected database version: $version"
            warn "Confirm that this version is compatible with your Reviactyl release."

            read -r -p "Type CONTINUE to accept this risk: " ans

            [[ "$ans" == "CONTINUE" ]] || {
                info "Cancelled; panel files have not been replaced."
                return 2
            }
        fi
    fi

    return 0
}

make_backup() {
    local stamp

    stamp="$(date +%Y%m%d-%H%M%S)"
    install -d -m 700 "$BACKUP_ROOT"
    BACKUP_DIR="$BACKUP_ROOT/$stamp"
    install -d -m 700 "$BACKUP_DIR"

    info "Backing up panel files..."

    tar -czpf "$BACKUP_DIR/panel-files.tar.gz" \
        -C "$(dirname "$PANEL_DIR")" "$(basename "$PANEL_DIR")"

    tar -tzf "$BACKUP_DIR/panel-files.tar.gz" >/dev/null || {
        fail "Panel file backup verification failed."
        return 1
    }

    info "Backing up database '$DB_DATABASE'..."

    if ! MYSQL_PWD="$DB_PASSWORD" "$DUMP_BIN" \
        --host="$DB_HOST" --port="$DB_PORT" \
        --user="$DB_USERNAME" --single-transaction --quick \
        --routines --triggers --events --add-drop-table \
        "$DB_DATABASE" > "$BACKUP_DIR/database.sql"; then

        rm -f "$BACKUP_DIR/database.sql"
        fail "Database backup failed. Stopping."
        return 1
    fi

    [[ -s "$BACKUP_DIR/database.sql" ]] || {
        fail "Database dump is empty."
        return 1
    }

    printf '%s\n' "$PANEL_DIR" > "$BACKUP_DIR/panel_path.txt"
    printf '%s\n' "$DB_DATABASE" > "$BACKUP_DIR/database_name.txt"

    chmod 600 "$BACKUP_DIR"/*
    printf '%s\n' "$BACKUP_DIR" > "$BACKUP_ROOT/LATEST"
    chmod 600 "$BACKUP_ROOT/LATEST"

    ok "Backup completed: $BACKUP_DIR"
}

install_dependencies() {
    local version f
    local -a versions=()

    PHP_VERSION="$(php -r \
        'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"

    [[ -n "$PHP_VERSION" ]] || {
        fail "PHP CLI is not installed."
        return 1
    }

    if [[ "$(printf '%s\n' 8.3 "$PHP_VERSION" | sort -V | head -n1)" != "8.3" ]]; then
        fail "PHP 8.3 or newer is required; found $PHP_VERSION."
        return 1
    fi

    versions+=("$PHP_VERSION")

    for f in /etc/php/*/fpm/php.ini; do
        [[ -f "$f" ]] || continue
        version="$(awk -F/ '{print $4}' <<< "$f")"
        [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] && versions+=("$version")
    done

    mapfile -t versions < <(printf '%s\n' "${versions[@]}" | sort -Vu)

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl ca-certificates tar gzip unzip git

    for version in "${versions[@]}"; do
        apt-get install -y \
            "php${version}-cli" \
            "php${version}-intl" \
            "php${version}-bcmath" \
            "php${version}-gd" \
            "php${version}-mysql" \
            "php${version}-mbstring" \
            "php${version}-xml" \
            "php${version}-curl" \
            "php${version}-zip" \
            "php${version}-redis"
    done

    if ! command -v composer >/dev/null 2>&1; then
        apt-get install -y composer
    fi

    composer --version
}

on_error() {
    local code="${1:-1}" line="${2:-unknown}"

    trap - ERR
    set +e

    echo
    fail "Command failed (exit $code, line $line)."

    if [[ -n "$OLD_DIR" && -d "$OLD_DIR" ]]; then
        warn "Restoring the previous application files."

        [[ ! -e "$PANEL_DIR" ]] ||
            mv "$PANEL_DIR" "${PANEL_DIR}.failed-$(date +%Y%m%d-%H%M%S)"

        mv "$OLD_DIR" "$PANEL_DIR"

        warn "Previous files restored."
        warn "If database migrations ran, review: ${BACKUP_DIR:-unknown}/database.sql"

        systemctl restart php8.3-fpm 2>/dev/null || true

        if nginx -t; then
            systemctl reload nginx 2>/dev/null || true
        fi
    else
        warn "Live panel files were not switched. Any backup is preserved."
    fi

    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi

    exit "$code"
}

install_reviactyl() {
    local ans archive extract source stage f rc
    local web_user=www-data web_group=www-data

    check_panel
    check_os
    read_db_config

    if check_db_version; then
        :
    else
        rc=$?
        [[ "$rc" -eq 2 ]] && return 0
        return "$rc"
    fi

    banner

    printf '%bWARNING: FULL PANEL REPLACEMENT, NOT A CSS-ONLY THEME.%b\n' \
        "$YELLOW" "$RESET"

    echo "A panel files and database backup will be made first."
    echo "The release will be checked before the live application is switched."

    read -r -p "Type MIGRATE to continue: " ans

    [[ "$ans" == "MIGRATE" ]] || {
        info "Cancelled. No panel files were changed."
        return 0
    }

    make_backup
    install_dependencies

    WORK_DIR="$(mktemp -d "$(dirname "$PANEL_DIR")/.reviactyl-stage.XXXXXX")"
    archive="$WORK_DIR/panel.tar.gz"
    extract="$WORK_DIR/extracted"
    stage="$WORK_DIR/stage"

    mkdir -p "$extract" "$stage"

    info "Downloading the latest Reviactyl release..."

    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 \
        "$RELEASE_URL" -o "$archive"

    gzip -t "$archive"

    # Avoid tar | grep -q: with pipefail, grep can close the pipe early.
    tar -tzf "$archive" > "$WORK_DIR/archive.list"

    info "Extracting and validating the release..."
    tar -xzf "$archive" -C "$extract"

    source=""

    if [[ -f "$extract/artisan" &&
          -f "$extract/composer.json" &&
          -f "$extract/composer.lock" &&
          -d "$extract/public" ]]; then
        source="$extract"
    else
        while IFS= read -r -d '' f; do
            if [[ -f "$f/composer.json" &&
                  -f "$f/composer.lock" &&
                  -d "$f/public" ]]; then
                source="$f"
                break
            fi
        done < <(
            find "$extract" -mindepth 1 -maxdepth 5 \
                -type f -name artisan -not -path '*/vendor/*' \
                -printf '%h\0' 2>/dev/null
        )
    fi

    [[ -n "$source" ]] || {
        fail "Release archive does not contain a valid Laravel panel root."
        fail "No live application files have been switched."
        return 1
    }

    cp -a "$source/." "$stage/"
    cp -p "$PANEL_DIR/.env" "$stage/.env"

    if [[ -d "$PANEL_DIR/storage" ]]; then
        rm -rf "$stage/storage"
        cp -a "$PANEL_DIR/storage" "$stage/storage"
    fi

    for f in public extensions; do
        if [[ -d "$PANEL_DIR/$f" ]]; then
            mkdir -p "$stage/$f"
            cp -an "$PANEL_DIR/$f/." "$stage/$f/"
        fi
    done

    info "Installing and verifying Composer dependencies..."

    (
        cd "$stage"
        COMPOSER_ALLOW_SUPERUSER=1 composer install \
            --no-dev --prefer-dist --optimize-autoloader --no-interaction
        COMPOSER_ALLOW_SUPERUSER=1 composer check-platform-reqs --no-dev
        php artisan --version
    )

    OLD_DIR="${PANEL_DIR}.pre-reviactyl-$(date +%Y%m%d-%H%M%S)"

    info "Switching to the prepared release..."

    mv "$PANEL_DIR" "$OLD_DIR"
    mv "$stage" "$PANEL_DIR"

    if ! id www-data >/dev/null 2>&1 && id nginx >/dev/null 2>&1; then
        web_user=nginx
        web_group=nginx
    fi

    install -d -o "$web_user" -g "$web_group" -m 775 \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/storage/logs" \
        "$PANEL_DIR/bootstrap/cache"

    chown -R "$web_user:$web_group" \
        "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

    chmod -R ug+rwX "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    chown root:"$web_group" "$PANEL_DIR/.env"
    chmod 640 "$PANEL_DIR/.env"

    info "Running database migrations..."

    (
        cd "$PANEL_DIR"
        php artisan migrate --seed --force
        php artisan optimize:clear
        php artisan queue:restart
    )

    while IFS= read -r f; do
        systemctl restart "$f" || warn "Could not restart $f"
    done < <(
        systemctl list-unit-files --type=service --no-legend |
        awk '$1 ~ /^php[0-9]+\.[0-9]+-fpm\.service$/ {
            sub(/\.service$/, "", $1); print $1
        }'
    )

    nginx -t
    systemctl reload nginx

    systemctl restart pteroq.service 2>/dev/null || true
    systemctl restart reviq.service 2>/dev/null || true

    ok "Migration commands completed."

    echo "Backup: $BACKUP_DIR"
    echo "Previous application: $OLD_DIR"

    warn "Test login, servers, nodes and queues before removing the old folder."
    warn "If migrations failed, the database backup is retained for recovery."

    rm -rf -- "$WORK_DIR"
    WORK_DIR=""
}

main() {
    local choice

    require_root
    check_os

    while true; do
        banner

        printf '%b[1]%b Install / migrate to Reviactyl\n' "$GREEN" "$RESET"
        printf '%b[2]%b Exit\n\n' "$GREEN" "$RESET"

        read -r -p "Select option [1-2]: " choice || return 0

        case "$choice" in
            1)
                install_reviactyl
                read -r -p "Press ENTER to return to menu..." _ || true
                ;;
            2)
                echo "Goodbye!"
                return 0
                ;;
            *)
                warn "Choose option 1 or 2."
                sleep 1
                ;;
        esac
    done
}

trap 'on_error $? $LINENO' ERR
main "$@"

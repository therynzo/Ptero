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

    local table_count
    table_count="$(MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USERNAME" "$DB_DATABASE" -Nse 'SHOW TABLES' | wc -l)" || {
        fail 'Could not read tables from the configured database. Check DB credentials and access.'; return 1;
    }
    if (( table_count == 0 )); then
        fail "Database '$DB_DATABASE' has no tables. Refusing to migrate an empty/unverified database."; return 1
    fi
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
    apt-get install -y curl ca-certificates tar gzip unzip git python3 redis-server
    for v in "${versions[@]}"; do
        packages=("php${v}-cli" "php${v}-common" "php${v}-intl" "php${v}-bcmath" "php${v}-gd" "php${v}-mysql" "php${v}-mbstring" "php${v}-xml" "php${v}-curl" "php${v}-zip" "php${v}-redis")
        # FPM is installed only if that PHP version already has FPM configured or it is the CLI version.
        if [[ -f "/etc/php/$v/fpm/php.ini" || "$v" == "$PHP_VERSION" ]]; then packages+=("php${v}-fpm"); fi
        apt-get install -y "${packages[@]}"
    done

    local ext modules
    modules="$(php -m 2>/dev/null | tr '[:upper:]' '[:lower:]')" || {
        fail "Could not read PHP modules for PHP CLI ($PHP_VERSION)."; return 1;
    }
    for ext in intl bcmath gd mysqli pdo_mysql mbstring xml curl zip; do
        if ! grep -qx "$ext" <<< "$modules"; then
            fail "PHP extension '$ext' is still unavailable in PHP CLI ($PHP_VERSION)."; return 1
        fi
    done
    systemctl enable --now redis-server >/dev/null 2>&1 || warn 'Redis service could not be enabled automatically; verify Redis is configured.'
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
    local ver numeric major minor
    ver="$(MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USERNAME" "$DB_DATABASE" -Nse 'SELECT VERSION()' 2>/dev/null || true)"
    if [[ -z "$ver" ]]; then
        warn 'Could not query the database version. Continuing only after a verified backup.'
        return 0
    fi
    info "Database server: $ver"
    # Reviactyl installation documentation lists MySQL 5.7.22+ or MariaDB 10.2+.

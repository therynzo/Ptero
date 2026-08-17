#!/bin/bash
set -e

# ====================================================
#       THERYNZO PTERODACTYL MASTER INSTALLER
# ====================================================

# --- COLORS & STYLING ---
RED='\033[0;31m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'
PHP_VERSION="8.3"
GITHUB_REPO="pterodactyl/panel"

# --- UI HELPER FUNCTIONS ---
show_banner() {
    clear
    echo -e "${RED}"
    cat << "EOF" | while read -r line; do echo "$line"; sleep 0.05; done
  _______ _          _____                        
 |__   __| |        |  __ \                       
    | |  | |__   ___| |__) |   _ _ __  _______  
    | |  | '_ \ / _ \  _  / | | | '_ \|__  / _ \ 
    | |  | | | |  __/ | \ \ |_| | | | | / / (_) |
    |_|  |_| |_|\___|_|  \_\__,_|_| |_|/___|\___/ 
EOF
    echo -e "           ${WHITE}PREMIUM PTERODACTYL MASTER SYSTEM${NC}"
    echo -e "${RED}────────────────────────────────────────────────────────────${NC}"
}

show_header() {
    clear
    show_banner
    echo -e "${RED}  Current Module: ${WHITE}$1${NC}"
    echo -e "${RED}────────────────────────────────────────────────────────────${NC}\n"
}

status_msg() {
    echo -e "  [${RED} ➤ ${NC}] ${WHITE}$1${NC}"
}

pause() {
    echo ""
    read -p "$(echo -e ${RED}"  Press [Enter] to return to main menu..."${NC})"
}

ask() {
    local label=$1
    local default=$2
    local var_name=$3
    echo -ne "  ${RED}•${NC} ${WHITE}$label${NC} ${GRAY}[$default]${NC}\n  ${RED}╰─>${NC} "
    read input
    if [ -z "$input" ]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

ask_timeout() {
    local label=$1
    local default=$2
    local var_name=$3
    echo -ne "  ${RED}•${NC} ${WHITE}$label${NC} ${GRAY}[$default]${NC}\n  ${RED}╰─>${NC} "
    if ! read -t 10 input; then
        echo -e "\n  ${RED}⌛ Timeout — using default: ${WHITE}$default${NC}"
        eval "$var_name=\"$default\""
        return
    fi
    if [ -z "$input" ]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

fetch_github_versions() {
    local repo=$1
    local json
    json=$(curl -sf "https://api.github.com/repos/$repo/releases?per_page=20" 2>/dev/null) || { return 1; }
    echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data:
    if r.get('prerelease', False):
        continue
    tag = r.get('tag_name', '')
    if tag.startswith('v'):
        print(tag)
" 2>/dev/null || return 1
}

select_version() {
    local repo=$1
    local var_name=$2
    local default="latest"
    echo -e "\n  ${RED}::${NC} ${WHITE}Available Panel Versions${NC}"
    local tags=() disp=() i=0
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tags+=("$tag")
        i=$((i+1))
        disp+=("  ${RED}$i.${NC} ${WHITE}$tag${NC}")
    done < <(fetch_github_versions "$repo" 2>/dev/null) || true

    if [[ ${#tags[@]} -eq 0 ]]; then
        eval "$var_name=\"$default\""
        return
    fi

    printf '%b\n' "${disp[@]}"
    local max=${#tags[@]}
    echo -ne "\n  ${RED}•${NC} ${WHITE}Select version [1-$max]${NC} ${GRAY}[1 = latest]${NC}\n  ${RED}╰─>${NC} "
    if ! read -t 10 choice; then
        eval "$var_name=\"${tags[0]}\""
        return
    fi
    if [[ -z "$choice" || "$choice" == "1" ]]; then
        eval "$var_name=\"${tags[0]}\""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $max ]]; then
        local idx=$((choice - 1))
        eval "$var_name=\"${tags[$idx]}\""
    else
        eval "$var_name=\"${tags[0]}\""
    fi
}

# ================== 1. INSTALL PANEL ==================
install_ptero() {
    show_header "PANEL INSTALLATION"
    
    ask "Panel Domain" "panel.vynx.cloud" DOMAIN
    ask "Admin Email" "admin@vynx.cloud" EMAIL
    ask "Admin Username" "admin" USERNAME
    ask_timeout "Admin Password" "admin" PASSWORD
    select_version "$GITHUB_REPO" "version_PANEL"

    echo -e "\n  ${RED}┌─[ REVIEW CONFIGURATION ]${NC}"
    echo -e "  ${RED}│${NC} ${WHITE}Domain:${NC}   $DOMAIN"
    echo -e "  ${RED}│${NC} ${WHITE}Email:${NC}    $EMAIL"
    echo -e "  ${RED}│${NC} ${WHITE}User:${NC}     $USERNAME"
    echo -e "  ${RED}│${NC} ${WHITE}Version:${NC}  $version_PANEL"
    echo -e "  ${RED}└───────────────────────────${NC}"

    while true; do
        echo -ne "\n  ${RED}Start Installation?${NC} ${WHITE}(y/n)${NC}${GRAY}:${NC} "
        read -n 1 -r CONFIRM
        echo ""
        case $CONFIRM in
            [Yy]* ) status_msg "Proceeding to deployment..."; break ;;
            [Nn]* ) status_msg "Installation aborted by user."; return ;;
            * ) echo -e "  ${GRAY}Invalid input. Enter y or n.${NC}" ;;
        esac
    done

    apt update && apt install -y curl apt-transport-https ca-certificates gnupg unzip git tar sudo lsb-release
    OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

    if [[ "$OS" == "ubuntu" ]]; then
        apt install -y software-properties-common
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    elif [[ "$OS" == "debian" ]]; then
        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg
        echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/sury-php.list
    fi

    rm -f /usr/share/keyrings/redis-archive-keyring.gpg
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list

    apt update
    apt install -y php${PHP_VERSION} php${PHP_VERSION}-{cli,fpm,common,mysql,mbstring,bcmath,xml,zip,curl,gd,tokenizer,ctype,simplexml,dom} mariadb-server nginx redis-server
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    if [[ "$version_PANEL" == "latest" ]]; then
        curl -Lso panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    else
        curl -Lso panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/${version_PANEL}/panel.tar.gz"
    fi
    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    DB_NAME=panel
    DB_USER=pterodactyl
    DB_PASS=$(openssl rand -base64 14)
    mariadb -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null || true
    mariadb -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};" 2>/dev/null || true
    mariadb -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
    mariadb -e "FLUSH PRIVILEGES;"

    if [ ! -f ".env.example" ]; then
        curl -Lo .env.example https://raw.githubusercontent.com/pterodactyl/panel/develop/.env.example
    fi
    cp .env.example .env
    sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" .env
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env
    echo "APP_ENVIRONMENT_ONLY=false" >> .env
    echo 'RECAPTCHA_ENABLED=false' >> .env

    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    php artisan migrate --seed --force

    chown -R www-data:www-data /var/www/pterodactyl/*
    apt install -y cron
    systemctl enable --now cron
    (crontab -l 2>/dev/null | grep -v "artisan schedule:run"; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

    mkdir -p /etc/certs/panel
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=NA/ST=NA/L=NA/O=NA/CN=${DOMAIN}" -keyout /etc/certs/panel/privkey.pem -out /etc/certs/panel/fullchain.pem

    cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    ssl_certificate /etc/certs/panel/fullchain.pem;
    ssl_certificate_key /etc/certs/panel/privkey.pem;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    nginx -t && systemctl restart nginx

    cat > /etc/systemd/system/pteroq.service << 'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now redis-server pteroq.service

    php artisan p:user:make -n --email="$EMAIL" --username="${USERNAME}" --password="$PASSWORD" --admin=1 --name-first=Admin --name-last=User
    
    echo -e "\n  ${RED}DEPLOYMENT COMPLETE${NC}"
    echo -e "  ${WHITE}URL : https://$DOMAIN${NC}"
    echo -e "  ${WHITE}User: $USERNAME${NC}"
    echo -e "  ${WHITE}Pass: $PASSWORD${NC}"
    pause
}

# ================== 2. USER MANAGEMENT ==================
create_user() {
    show_header "USER MANAGEMENT"

    if [ ! -d /var/www/pterodactyl ]; then
        status_msg "Panel directory not found. Install panel first."
        pause
        return
    fi

    echo -e "  ${RED}[1]${NC} ${WHITE}Custom User Create${NC}"
    echo -e "  ${RED}[2]${NC} ${WHITE}Auto Create Admin User${NC}\n"
    read -p "$(echo -e ${RED}"  Choose option: "${NC})" choice

    cd /var/www/pterodactyl || exit

    if [ "$choice" = "1" ]; then
        php artisan p:user:make
    elif [ "$choice" = "2" ]; then
        USERNAME="user$(openssl rand -hex 2)"
        PASSWORD="$(openssl rand -base64 10)"
        EMAIL="$(openssl rand -base64 4)@email.com"
        php artisan p:user:make -n --email=${EMAIL} --username=${USERNAME} --password=${PASSWORD} --admin=1 --name-first=Admin --name-last=User
        echo -e "\n  ${WHITE}Username: $USERNAME${NC}"
        echo -e "  ${WHITE}Password: $PASSWORD${NC}"
        echo -e "  ${WHITE}Email:    $EMAIL${NC}"
    fi
    pause
}

# ================== 3. UPDATE PANEL ==================
update_panel() {
    show_header "SYSTEM UPDATE"

    if [ ! -d /var/www/pterodactyl ]; then
        status_msg "Panel not found."
        pause
        return
    fi

    select_version "$GITHUB_REPO" "version_PANEL"
    
    status_msg "Putting panel into Maintenance Mode..."
    cd /var/www/pterodactyl
    php artisan down
    rm -rf /var/www/pterodactyl/*
    
    if [[ "$version_PANEL" == "latest" ]]; then
        curl -Lso panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    else
        curl -Lso panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/${version_PANEL}/panel.tar.gz"
    fi
    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan view:clear
    php artisan config:clear
    php artisan migrate --seed --force
    chown -R www-data:www-data /var/www/pterodactyl/*
    php artisan queue:restart
    php artisan up

    status_msg "Panel Updated Successfully."
    pause
}

# ================== 4. DOMAIN / SSL ==================
config_ssl() {
    show_header "NGINX & SSL CONFIGURATOR"

    echo -e "  ${RED}[1]${NC} ${WHITE}SSL / HTTPS (Standard)${NC}"
    echo -e "  ${RED}[2]${NC} ${WHITE}No SSL / HTTP (Insecure)${NC}"
    echo -e "  ${RED}[3]${NC} ${WHITE}Auto SSL Generator (Certbot)${NC}\n"
    read -p "$(echo -e ${RED}"  Select option [1-3]: "${NC})" OPTION

    echo ""
    read -p "$(echo -e ${RED}"  Enter your Domain: "${NC})" DOMAIN
    cd /var/www/pterodactyl || { status_msg "Pterodactyl directory not found!"; pause; return; }

    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/pterodactyl.conf

    if [ "$OPTION" == "1" ]; then
        FULLCHAIN="/etc/certs/panel/fullchain.pem"
        PRIVKEY="/etc/certs/panel/privkey.pem"
        sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env

        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    ssl_certificate ${FULLCHAIN};
    ssl_certificate_key ${PRIVKEY};
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    location ~ /\.ht { deny all; }
}
EOF

    elif [ "$OPTION" == "2" ]; then
        sed -i "s|APP_URL=.*|APP_URL=http://${DOMAIN}|g" .env
        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    location ~ /\.ht { deny all; }
}
EOF

    elif [ "$OPTION" == "3" ]; then
        EMAIL="ssl$(tr -dc a-z0-9 </dev/urandom | head -c6)@vynx.cloud"
        apt update -y
        apt install certbot python3-certbot-nginx -y
        certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m ${EMAIL} --redirect
        if [ $? -eq 0 ]; then
            status_msg "SSL Installed Successfully!"
        else
            status_msg "SSL Generation Failed. Check DNS."
        fi
        pause
        return
    fi

    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    nginx -t && systemctl restart nginx
    status_msg "Nginx Configured!"
    pause
}

# ================== 5. UNINSTALL ==================
uninstall_ptero() {
    show_header "UNINSTALLATION"
    
    echo -e "${RED}  WARNING: This will delete all panel data and databases!${NC}"
    read -p "$(echo -e ${RED}"  Proceed? (y/N): "${NC})" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        status_msg "Uninstallation cancelled."
        pause
        return
    fi

    systemctl stop pteroq.service 2>/dev/null || true
    systemctl disable pteroq.service 2>/dev/null || true
    rm -f /etc/systemd/system/pteroq.service
    systemctl daemon-reload
    crontab -l | grep -v 'php /var/www/pterodactyl/artisan schedule:run' | crontab - || true
    rm -rf /var/www/pterodactyl
    mariadb -e "DROP DATABASE IF EXISTS panel;" 2>/dev/null || true
    mariadb -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null || true
    mariadb -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    systemctl reload nginx || true

    status_msg "Panel removed successfully (Wings untouched)."
    pause
}

# ================== 6. PHPMYADMIN ==================
install_phpmyadmin() {
    show_header "PHPMYADMIN INSTALLATION"

    ask "Domain" "phpmyadmin.vynx.cloud" PMA_DOMAIN
    ask "Database Name" "phpmyadmin" PMA_DB
    ask "Database User" "phpmyadmin" PMA_USER
    ask "Database Pass" "phpmyadmin" PMA_PASS

    INSTALL_DIR="/var/www/phpmyadmin"
    SSL_DIR="/etc/certs/phpMyAdmin"

    apt update
    apt install -y wget tar nginx openssl php-fpm mariadb-server

    mkdir -p "$INSTALL_DIR/tmp"
    cd "$INSTALL_DIR"
    wget -O phpMyAdmin.tar.gz https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-english.tar.gz
    tar -xzf phpMyAdmin.tar.gz
    PMA_DIR=$(find . -maxdepth 1 -type d -name "phpMyAdmin-*-english" | head -n1)
    mv "$PMA_DIR"/* .
    rm -rf "$PMA_DIR" phpMyAdmin.tar.gz

    mkdir -p config
    chmod o+rw config
    cp config.sample.inc.php config/config.inc.php
    chmod o+w config/config.inc.php

    chown -R www-data:www-data *
    chown -R www-data:www-data "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    mariadb -e "CREATE USER IF NOT EXISTS '${PMA_USER}'@'127.0.0.1' IDENTIFIED BY '${PMA_PASS}';" 2>/dev/null || true
    mariadb -e "CREATE DATABASE IF NOT EXISTS ${PMA_DB};" 2>/dev/null || true
    mariadb -e "GRANT ALL PRIVILEGES ON ${PMA_DB}.* TO '${PMA_USER}'@'127.0.0.1' WITH GRANT OPTION;" 2>/dev/null || true
    mariadb -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    mkdir -p "$SSL_DIR"
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=NA/ST=NA/L=NA/O=NA/CN=$PMA_DOMAIN" -keyout "$SSL_DIR/privkey.pem" -out "$SSL_DIR/fullchain.pem"
    
    PHP_SOCKET=$(find /run/php -name "php*-fpm.sock" | head -n1)

    cat > /etc/nginx/sites-available/phpmyadmin.conf <<EOF
server {
    listen 80;
    server_name $PMA_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $PMA_DOMAIN;
    root $INSTALL_DIR;
    index index.php;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    ssl_certificate $SSL_DIR/fullchain.pem;
    ssl_certificate_key $SSL_DIR/privkey.pem;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:$PHP_SOCKET;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/phpmyadmin.conf
    nginx -t && systemctl restart nginx
    
    status_msg "phpMyAdmin Deployment Complete!"
    echo -e "  ${WHITE}URL: https://$PMA_DOMAIN${NC}"
    pause
}

# ===================== MAIN MENU LOOP =====================
while true; do
    clear
    show_banner
    
    echo -e "${RED} ┌───────────────────────────────────────────────────────┐${NC}"
    if [ -d "/var/www/pterodactyl" ]; then
        echo -e "${RED} │${NC} ${WHITE}PANEL STATUS:${NC} ${WHITE}INSTALLED ✔${NC}                             ${RED}│${NC}"
    else
        echo -e "${RED} │${NC} ${WHITE}PANEL STATUS:${NC} ${WHITE}NOT INSTALLED ✘${NC}                         ${RED}│${NC}"
    fi
    echo -e "${RED} ├───────────────────────────────────────────────────────┤${NC}"
    echo -e "${RED} │${NC}                                                       ${RED}│${NC}"
    echo -e "${RED} │${NC}  ${RED}[1]${NC} ${WHITE}Install Panel${NC}   ${GRAY}:: (Fresh Installation)${NC}          ${RED}│${NC}"
    echo -e "${RED} │${NC}  ${RED}[2]${NC} ${WHITE}User Management${NC} ${GRAY}:: (Add Admin/User)${NC}              ${RED}│${NC}"
    echo -e "${RED} │${NC}  ${RED}[3]${NC} ${WHITE}Update Panel${NC}    ${GRAY}:: (Latest Release)${NC}              ${RED}│${NC}"
    echo -e "${RED} │${NC}  ${RED}[4]${NC} ${WHITE}Domain & SSL${NC}    ${GRAY}:: (Change Domain/SSL)${NC}           ${RED}│${NC}"
    echo -e "${RED} │${NC}  ${RED}[5]${NC} ${WHITE}Uninstall${NC}       ${GRAY}:: (Remove All Data)${NC}             ${RED}│${NC}"
    echo -e "${RED} │${NC}  ${RED}[6]${NC} ${WHITE}phpMyAdmin${NC}      ${GRAY}:: (Install phpMyAdmin)${NC}          ${RED}│${NC}"
    echo -e "${RED} │${NC}                                                       ${RED}│${NC}"
    echo -e "${RED} │${NC}  ${WHITE}[0] Exit System${NC}                                      ${RED}│${NC}"
    echo -e "${RED} └───────────────────────────────────────────────────────┘${NC}"
    echo ""
    read -p "$(echo -e ${RED}${BOLD}"  root@rynzo:~# "${NC})" choice

    case $choice in
        1) install_ptero ;;
        2) create_user ;;
        3) update_panel ;;
        4) config_ssl ;;
        5) uninstall_ptero ;;
        6) install_phpmyadmin ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}  Invalid option selected...${NC}"; sleep 1 ;;
    esac
done

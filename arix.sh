#!/bin/bash
set -e

# ==========================================
# ARIX THEME INSTALLER (ADVANCED & ANIMATED)
# ==========================================

API_URL="http://78.154.103.27:13915/api/verify"

# --- Colors & Typography ---
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# --- Custom Loggers ---
info() { echo -e "${BLUE}[ℹ] ${WHITE}$1${NC}"; }
success() { echo -e "${GREEN}[✔] ${WHITE}$1${NC}"; }
warning() { echo -e "${YELLOW}[⚠] ${WHITE}$1${NC}"; }
error() { echo -e "${RED}[✖] ${WHITE}$1${NC}"; }
step() { echo -e "\n${MAGENTA}➤ ${CYAN}Step $1: ${WHITE}$2${NC}"; }

# --- Animation Functions ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep -w $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r${MAGENTA} [%c] ${WHITE}Working... Please wait${NC}" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r\033[K" # Clear the spinner line completely
}

typewriter() {
    local text="$1"
    local delay=0.015
    for (( i=0; i<${#text}; i++ )); do
        echo -ne "${text:$i:1}"
        sleep $delay
    done
    echo ""
}

# --- Banner Function ---
show_banner() {
    clear
    echo -e "${MAGENTA}"
    echo '    █████╗ ██████╗ ██╗██╗  ██╗'
    echo '   ██╔══██╗██╔══██╗██║╚██╗██╔╝'
    echo '   ███████║██████╔╝██║ ╚███╔╝ '
    echo '   ██╔══██║██╔══██╗██║ ██╔██╗ '
    echo '   ██║  ██║██║  ██║██║██╔╝ ██╗'
    echo '   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝'
    echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ${NC}"
    typewriter "          Advanced Pterodactyl Theme Installer"
    echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ${NC}\n"
}

DOWNLOAD_URL=""
LICENSE_TYPE=""
LICENSE_VERSION=""

# ==========================================
# DEPENDENCY CHECK (Node 22+ & Yarn)
# ==========================================
check_dependencies() {
    info "Verifying Node.js and Yarn requirements..."
    set +e
    
    # Node.js Check
    if command -v node >/dev/null 2>&1; then
        NODE_VER=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$NODE_VER" -lt 22 ]; then
            warning "Node.js version is below 22. Updating to Node 22..."
            (curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1 && apt-get install -y nodejs > /dev/null 2>&1) & spinner $!
        else
            success "Node.js v22+ is already installed."
        fi
    else
        warning "Node.js not found. Installing Node 22..."
        (curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1 && apt-get install -y nodejs > /dev/null 2>&1) & spinner $!
    fi
    
    # Yarn Check
    if ! command -v yarn >/dev/null 2>&1; then
        warning "Yarn not found. Installing Yarn..."
        (npm install -g yarn > /dev/null 2>&1) & spinner $!
        success "Yarn installed successfully."
    else
        success "Yarn is already installed."
    fi
    set -e
}

# ==========================================
# MENUS
# ==========================================
menu_210() {
    while true; do
        show_banner
        echo -e "${WHITE}Select Edition for ${GREEN}Arix v2.1.0${WHITE}:${NC}\n"
        echo -e "${CYAN}  [ 1 ] ${WHITE}Standard Edition (Non-Blueprint)"
        echo -e "${CYAN}  [ 2 ] ${WHITE}Blueprint Edition"
        echo -e "${CYAN}  [ 3 ] ${WHITE}Go Back${NC}\n"
        
        echo -ne "${MAGENTA} ➜ ${WHITE}Choose an option: ${CYAN}"
        read choice_210
        echo -ne "${NC}"
        
        case $choice_210 in
            1) 
                LICENSE_TYPE="non-blueprint"
                LICENSE_VERSION="2.1.0"
                DOWNLOAD_URL="https://raw.githubusercontent.com/sdgamer8263-sketch/pterodactyl_extention1/main/sd/v210/pterodactyl.zip"
                break 2 
                ;;
            2) 
                LICENSE_TYPE="blueprint"
                LICENSE_VERSION="2.1.0"
                DOWNLOAD_URL="https://raw.githubusercontent.com/sdgamer8263-sketch/pterodactyl_extention1/main/pterodactyl.zip"
                break 2 
                ;;
            3) break ;;
            *) warning "Invalid selection."; sleep 1 ;;
        esac
    done
}

menu_208() {
    while true; do
        show_banner
        echo -e "${WHITE}Select Edition for ${GREEN}Arix v2.0.8${WHITE}:${NC}\n"
        echo -e "${CYAN}  [ 1 ] ${WHITE}Standard Edition (Non-Blueprint)"
        echo -e "${CYAN}  [ 2 ] ${WHITE}Blueprint Edition"
        echo -e "${CYAN}  [ 3 ] ${WHITE}Go Back${NC}\n"
        
        echo -ne "${MAGENTA} ➜ ${WHITE}Choose an option: ${CYAN}"
        read choice_208
        echo -ne "${NC}"
        
        case $choice_208 in
            1) 
                LICENSE_TYPE="non-blueprint"
                LICENSE_VERSION="2.0.8"
                DOWNLOAD_URL="https://raw.githubusercontent.com/sdgamer8263-sketch/pterodactyl_extention1/main/sd/v208/pterodactyl.zip"
                break 2 
                ;;
            2) 
                LICENSE_TYPE="blueprint"
                LICENSE_VERSION="2.0.8"
                DOWNLOAD_URL="https://raw.githubusercontent.com/sdgamer8263-sketch/pterodactyl_extention1/main/sd/av1pterodactyl.zip"
                break 2 
                ;;
            3) break ;;
            *) warning "Invalid selection."; sleep 1 ;;
        esac
    done
}

while true; do
    show_banner
    typewriter " Welcome to the Arix Theme setup. Select Version:"
    echo ""
    echo -e "${CYAN}  [ 1 ] ${WHITE}Arix v2.1.0 ${GREEN}(Latest)${NC}"
    echo -e "${CYAN}  [ 2 ] ${WHITE}Arix v2.0.8 ${YELLOW}(Legacy)${NC}"
    echo -e "${RED}  [ Q ] ${WHITE}Abort Installation${NC}\n"
    
    echo -ne "${MAGENTA} ➜ ${WHITE}Choose an option: ${CYAN}"
    read main_choice
    echo -ne "${NC}"
    
    case $main_choice in
        1) menu_210 ;;
        2) menu_208 ;;
        q|Q) echo ""; warning "Installation aborted."; exit 0 ;;
        *) echo ""; warning "Invalid selection. Try again."; sleep 1 ;;
    esac
    
    if [ -n "$DOWNLOAD_URL" ]; then break; fi
done

# ==========================================
# INSTALLATION PROCESS
# ==========================================
show_banner

check_dependencies

echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ${NC}"
echo -e "${WHITE}             INITIALIZING INSTALLATION            ${NC}"
echo -e "${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ${NC}"

set +e
(apt-get update -y > /dev/null 2>&1 && apt-get install -y unzip curl wget > /dev/null 2>&1) & spinner $!
set -e

if [ ! -d "/var/www/pterodactyl" ]; then
    error "Pterodactyl installation not found in /var/www/pterodactyl!"
    exit 1
fi
cd /var/www/pterodactyl

step "1/4" "Downloading Arix Theme Assets (v$LICENSE_VERSION - $LICENSE_TYPE)..."
(curl -sL -o pterodactyl.zip "$DOWNLOAD_URL") & spinner $!
success "Downloaded successfully."

step "2/4" "Extracting Core Files..."
(
    unzip -o pterodactyl.zip > /dev/null 2>&1
    if [ -d "pterodactyl" ]; then 
        cp -rf pterodactyl/* ./ 
        rm -rf pterodactyl 
    fi
    rm pterodactyl.zip 
) & spinner $!
success "Files extracted successfully."

step "3/4" "Injecting Modules..."
if [ "$LICENSE_VERSION" == "2.1.0" ]; then
    info "Applying Arix Patch Modules for v2.1.0..."
    cat << 'EOF' > app/Console/Commands/Arix.php
<?php

namespace Pterodactyl\Console\Commands;

use Illuminate\Console\Command;
use Symfony\Component\Console\Formatter\OutputFormatterStyle;
use Illuminate\Support\Facades\File;

class Arix extends Command
{
    protected $signature = "arix {action?}";
    protected $description = "All commands for Arix Theme for Pterodactyl.";

    public function handle()
    {
        $action = $this->argument("action");
        $title = new OutputFormatterStyle("#fff", null, ["bold"]);
        $this->output->getFormatter()->setStyle("title", $title);
        $b = new OutputFormatterStyle(null, null, ["bold"]);
        $this->output->getFormatter()->setStyle("b", $b);

        if ($action === null) {
            $this->line("\r\n            <title>\r\n            ░█████╗░██████╗░██╗██╗░░██╗\r\n            ██╔══██╗██╔══██╗██║╚██╗██╔╝\r\n            ███████║██████╔╝██║░╚███╔╝░\r\n            ██╔══██║██╔══██╗██║░██╔██╗░\r\n            ██║░░██║██║░░██║██║██╔╝╚██╗\r\n            ╚═╝░░╚═╝╚═╝░░╚═╝╚═╝╚═╝░░╚═╝\r\n\r\n           Thank you for purchasing Arix</title>\r\n\r\n           > php artisan arix (this window)\r\n           > php artisan arix install\r\n           > php artisan arix update\r\n           > php artisan arix uninstall\r\n            ");
        } else {
            $this->info("\n    Arix Theme\n    \n");
            if ($action === "install") {
                $this->install();
            } elseif ($action === "update") {
                $this->update();
            } elseif ($action === "uninstall") {
                $this->uninstall();
            } else {
                $this->error("Invalid action. Supported actions: install, update, uninstall");
            }
        }
    }

    public function installOrUpdate($isUpdate = false)
    {
        if ($isUpdate) {
            $this->info("\n    This command is not recommended to use. \n   This command skips frequently used files by addons during theme updating to avoid losing your addon customizations.\n   If you still experience an error after updating please contact us.");
        }

        $confirmation = $this->confirm("Are all the required dependencies installed from the readme file?", "yes");
        if (!$confirmation) {
            return;
        }

        $versions = File::directories("./arix");
        if (empty($versions)) {
            $this->info("No versions found in /arix directory.");
            return;
        }

        $version = basename($this->choice("Select a version:", $versions));
        $this->info("Installing Arix Theme {$version}...");

        $excludeOption = $isUpdate ? "--exclude='routes.ts' --exclude='getServer.ts' --exclude='admin.blade.php' --exclude='admin.php' --exclude='ServerTransformer.php'" : '';
        exec("rsync -a {$excludeOption} arix/{$version}/ ./");

        $directoryPath = app_path("Http/Controllers/Admin/Arix");
        File::makeDirectory($directoryPath, 0755, true, true);

        $filesOne = ["ArixController", "ArixAdvancedController", "ArixAnnouncementController", "ArixColorsController", "ArixComponentsController", "ArixDashboardController", "ArixLayoutController"];
        $this->info("Proceeding with the installation...");
        foreach ($filesOne as $file) {
            $this->aa($file, $version, $directoryPath);
            sleep(1);
        }

        $filesTwo = ["ArixLinkController", "ArixMailController", "ArixMetaController", "ArixPresetController", "ArixSocialController", "ArixStylingController"];
        foreach ($filesTwo as $file) {
            $this->aa($file, $version, $directoryPath);
            sleep(1);
        }

        $this->info("Migrating database...");
        $this->command("php artisan migrate --force");

        $this->info("Installing required packages...");
        $this->info("This can take a minute...");
        $this->command("yarn add react-email-editor react-colorful recharts@^2.15.4 ua-parser-js cronstrue react-day-picker jszip react-turnstile @dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities @types/md5 md5 react-icons@5.4.0 markdown-to-jsx@7.7.10 i18next-browser-languagedetector@7.2.1");

        $this->info("Compile translations...");
        $this->command("php artisan language:compile");

        $this->info("Building panel assets...");
        $this->info("This can take a minute...");
        $nodeVersion = shell_exec("node -v");
        $nodeVersion = (int) ltrim($nodeVersion, "v");
        if ($nodeVersion >= 17) {
            $this->info("Node.js version is v" . $nodeVersion . " (>= 17)");
            putenv("NODE_OPTIONS=--openssl-legacy-provider");
        } else {
            $this->info("Node.js version is v" . $nodeVersion . " (< 17)");
        }
        $this->command("yarn build:production");

        $this->info("Set permissions...");
        $this->command("chown -R www-data:www-data /var/www/pterodactyl/* " . base_path() . "/*");
        $this->command("chown -R nginx:nginx " . base_path() . "/*");
        $this->command("chown -R apache:apache " . base_path() . "/*");

        $this->info("Optimize application...");
        $this->command("php artisan optimize:clear");
        $this->command("php artisan optimize");

        $this->info("Restarting workers...");
        $this->command("php artisan queue:restart");

        $message = $isUpdate ? "│    Theme updated successfully   │" : "│   Theme installed successfully  │";
        $this->line("\n ╭───────────────────────────────╮\n │ │\n │ ╭─╴ {$message} ╶─╮ │\n │ ╰─╴ successfully ╶─╯ │\n │ │\n ╰───────────────────────────────╯\n ");
    }

    private function aa($filename, $version, $directoryPath)
    {
        $filePath = $directoryPath . "/" . $filename . ".php";
        $localSource = base_path("arix/" . $version . "/app/Http/Controllers/Admin/Arix/" . $filename . ".php");

        if (File::exists($localSource)) {
            $this->info(" -> Copying local {$filename}.php...");
            File::copy($localSource, $filePath);
        } else {
            $this->error("Fail: Could not find local {$filename}.php at {$localSource}.");
        }
    }
    
    public function install()
    {
        $this->info("Configuring environment...");
        sleep(1);
        $this->info("Loading modules...");
        sleep(1);
        
        $this->installOrUpdate();
        
        $this->info("Arix Theme installation completed safely!");
    }

    public function update()
    {
        $this->installOrUpdate(true);
    }

    private function uninstall()
    {
        $this->line("Uninstalling...");
        $this->command("php artisan down");
        $this->command("curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv");
        $this->command("chmod -R 755 storage/* bootstrap/cache");
        $this->command("composer install --no-dev --optimize-autoloader");
        $this->command("php artisan view:clear");
        $this->command("php artisan config:clear");
        $this->command("php artisan migrate --seed --force");
        $this->command("chown -R www-data:www-data " . base_path() . "/*");
        $this->command("chown -R nginx:nginx " . base_path() . "/*");
        $this->command("chown -R apache:apache " . base_path() . "/*");
        $this->command("php artisan queue:restart");
        $this->command("php artisan up");
        $this->info("Arix Theme uninstalled successfully.");
    }

    private function command($cmd)
    {
        return exec($cmd);
    }
}
EOF
    php artisan arix install
else
    info "Skipping Arix.php patch for legacy v2.0.8..."
fi
success "Modules injected!"

step "4/4" "Compiling Pterodactyl Panel (Production Build)..."
warning "This process takes 2-5 minutes. Please DO NOT close the terminal."
(
    yarn add xterm-addon-unicode11 > /dev/null 2>&1
    yarn build > /dev/null 2>&1
) & spinner $!
success "Panel compiled successfully!"

set +e

info "Applying Final Permissions & Caching..."
(
    curl -sL https://raw.githubusercontent.com/pterodactyl/panel/master/public/index.php -o public/index.php > /dev/null 2>&1
    chown -R www-data:www-data /var/www/pterodactyl 2>/dev/null
    chown -R nginx:nginx /var/www/pterodactyl 2>/dev/null
    find /var/www/pterodactyl -type d -exec chmod 755 {} \;
    find /var/www/pterodactyl -type f -exec chmod 644 {} \;
    chmod -R 775 storage/* bootstrap/cache/
    chown -R www-data:www-data /var/www/pterodactyl/*
) & spinner $!

# ==========================================
# COMPLETION
# ==========================================
echo ""
echo -e "${GREEN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ${NC}"
typewriter "    🎉 INSTALLATION COMPLETED SUCCESSFULLY! 🎉    "
echo -e "${GREEN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ${NC}"
echo -e "${CYAN} Your Pterodactyl Panel has been updated with Arix v${LICENSE_VERSION} (${LICENSE_TYPE}).${NC}"
echo -e "${WHITE} If you encounter any issues, try clearing your browser cache.${NC}\n"

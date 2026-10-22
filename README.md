bash <(curl -fsSL https://raw.githubusercontent.com/therynzo/Ptero/main/reviactyltheme.sh)



" curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs && npm install -g pnpm@11.18.0 && cd /var/www/pterodactyl && pnpm install --frozen-lockfile && f=resources/scripts/reviactyl/ui/Footer.tsx && test -f "$f" && stamp=$(date +%Y%m%d%H%M%S) && cp -p "$f" "$f.aliennode-$stamp.bak" && cp -a public/build "public/build.aliennode-$stamp.bak" && sed -i 's/Reviactyl&trade;/AlienNode/g; s|https://reviactyl.app|https://aliennode.in|g' "$f" && if pnpm run build; then php artisan optimize:clear && echo 'SUCCESS: AlienNode footer rebuilt'; else cp -p "$f.aliennode-$stamp.bak" "$f"; rm -rf public/build && cp -a "public/build.aliennode-$stamp.bak" public/build && echo 'BUILD FAILED: Previous source and assets restored'; exit 1; fi "




"bash <(curl -fsSL https://raw.githubusercontent.com/therynzo/Ptero/main/unknow.sh)"

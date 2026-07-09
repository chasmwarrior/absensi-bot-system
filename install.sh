#!/bin/bash
# Auto Installer for Absensi Bot System on Ubuntu (Nginx)

set -e

echo "==============================================="
echo "   ABSENSI BOT SYSTEM AUTO INSTALLER (NGINX)   "
echo "==============================================="
echo ""

echo "[1/8] Cleaning up previous installations (Fresh Install)..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true

WEB_DIR="/var/www/html/absensi"
if [ -d "$WEB_DIR" ]; then
    echo "Removing previous web directory $WEB_DIR..."
    rm -rf $WEB_DIR
fi

DB_NAME="absensi_chatbot"
if command -v mysql &> /dev/null; then
    echo "Dropping existing database if it exists..."
    mysql -u root -e "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
fi

echo "[2/8] Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "[3/8] Installing Nginx, PHP-FPM, MariaDB, and required extensions..."
# Stop Apache if it is running to free port 80
if systemctl is-active --quiet apache2; then
    echo "Stopping Apache to free port 80 for Nginx..."
    systemctl stop apache2
    systemctl disable apache2
fi

# We use php-fpm for Nginx. Assuming Ubuntu 22.04 defaults to php8.1-fpm
apt-get install -y nginx mariadb-server php-fpm php-mysql php-cli php-curl php-json php-mbstring unzip git

# Find installed PHP version dynamically (e.g. 8.1)
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo "Detected PHP version: $PHP_VER"

echo "[4/8] Configuring Database..."
systemctl start mariadb || service mysql start || true
systemctl enable mariadb || true

echo "Creating database if it doesn't exist..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || echo "Failed to create DB. Proceeding..."

echo "Configuring dedicated database user..."
DB_APP_USER="absensi_app"
DB_APP_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_APP_USER}'@'localhost' IDENTIFIED BY '${DB_APP_PASS}';"
mysql -u root -e "ALTER USER '${DB_APP_USER}'@'localhost' IDENTIFIED BY '${DB_APP_PASS}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_APP_USER}'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

echo "[5/8] Deploying application files..."
echo "Copying files to $WEB_DIR..."
mkdir -p $WEB_DIR
cp -r * $WEB_DIR/

echo "[6/8] Importing Database Schema..."
if [ -f "$WEB_DIR/db/absensi_chatbot.sql" ]; then
    sed -i 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' "$WEB_DIR/db/absensi_chatbot.sql"
    mysql -u root $DB_NAME < $WEB_DIR/db/absensi_chatbot.sql || echo "Failed to import SQL. Check your DB root credentials."
else
    echo "Database SQL file not found at $WEB_DIR/db/absensi_chatbot.sql"
fi

echo "[7/8] Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/absensi"
cat <<EOL > $NGINX_CONF
server {
    listen 80;
    server_name _;
    root /var/www/html/absensi;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ @rewrite;
    }

    # Rewrite rules similar to .htaccess
    location @rewrite {
        # Redirect /home to index.php
        rewrite ^/home$ /index.php last;

        # If file exists as .php, rewrite to it (removes need for .php extension in URLs)
        if (-f \$document_root\$uri.php) {
            rewrite ^(.*)$ \$1.php last;
        }
    }

    # Block direct access to certain directories
    location ^~ /app/ {
        # Allow webhooks
        location ~* (webhook_telegram\.php|webhook_whatsapp\.php)$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        }
        deny all;
    }

    location ^~ /inc/ {
        deny all;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # Block access to hidden files like .htaccess and config files
    location ~ /\.(?!well-known).* {
        deny all;
    }
    location ~ ^/(config\.php|koneksi\.php)$ {
        deny all;
    }
}
EOL

# Enable site and disable default if necessary
ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
# We can remove default site to avoid conflict on port 80 if necessary, but absensi is on / (root) so we probably should.
rm -f /etc/nginx/sites-enabled/default

# Fix permissions
chown -R www-data:www-data $WEB_DIR
chmod -R 755 $WEB_DIR


echo "[7.5/8] Updating inc/config.php with new database credentials..."
sed -i "s/define('DB_USER', '.*');/define('DB_USER', '${DB_APP_USER}');/g" $WEB_DIR/inc/config.php
sed -i "s/define('DB_PASS', '.*');/define('DB_PASS', '${DB_APP_PASS}');/g" $WEB_DIR/inc/config.php

echo "[8/8] Restarting Nginx and PHP-FPM..."
systemctl restart php${PHP_VER}-fpm
nginx -t
systemctl restart nginx

echo "==============================================="
echo "   INSTALLATION COMPLETE!                      "
echo "==============================================="
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "You can now access the system at:"
echo "http://${IP_ADDR}/"
echo ""
echo "Note: The app is now hosted directly at the domain root (http://domain.com/) instead of /absensi to ensure clean URL routing works perfectly with Nginx."
echo ""
echo "Default Login:"
echo "Username: admin"
echo "Password: (As per your database dump)"
echo "Make sure to update inc/config.php if you use a database password!"

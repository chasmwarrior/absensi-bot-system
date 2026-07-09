#!/bin/bash
# Auto Installer for Absensi Bot System on Ubuntu

set -e

echo "==============================================="
echo "   ABSENSI BOT SYSTEM AUTO INSTALLER (UBUNTU)  "
echo "==============================================="
echo ""

echo "[1/8] Cleaning up previous installations (Fresh Install)..."
# Start DB services to ensure we can drop the database
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true

# Remove previous web directory
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

echo "[3/8] Installing Apache, PHP, MariaDB, and required extensions..."
# Stop Nginx if it is running to free port 80
if systemctl is-active --quiet nginx; then
    echo "Stopping Nginx to free port 80 for Apache..."
    systemctl stop nginx
    systemctl disable nginx
fi

apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql php-cli php-curl php-json php-mbstring unzip git

echo "[4/8] Configuring Database..."
# Ensure MariaDB service is running
systemctl start mariadb || service mysql start || true
systemctl enable mariadb || true

echo "Creating database if it doesn't exist..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || echo "Failed to create DB. Proceeding..."

echo "[5/8] Deploying application files..."
echo "Copying files to $WEB_DIR..."
mkdir -p $WEB_DIR
cp -r * $WEB_DIR/
cp -r .htaccess $WEB_DIR/ 2>/dev/null || true

echo "[6/8] Importing Database Schema..."
if [ -f "$WEB_DIR/db/absensi_chatbot.sql" ]; then
    # Fix collation issue in MariaDB by replacing utf8mb4_0900_ai_ci with utf8mb4_unicode_ci
    sed -i 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' "$WEB_DIR/db/absensi_chatbot.sql"
    mysql -u root $DB_NAME < $WEB_DIR/db/absensi_chatbot.sql || echo "Failed to import SQL. Check your DB root credentials."
else
    echo "Database SQL file not found at $WEB_DIR/db/absensi_chatbot.sql"
fi

echo "[7/8] Setting correct permissions..."
chown -R www-data:www-data $WEB_DIR
chmod -R 755 $WEB_DIR

echo "[8/8] Restarting Apache..."
systemctl restart apache2 || true

echo "==============================================="
echo "   INSTALLATION COMPLETE!                      "
echo "==============================================="
# Output IP properly
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "You can now access the system at:"
echo "http://${IP_ADDR}/absensi"
echo ""
echo "Default Login:"
echo "Username: admin"
echo "Password: (As per your database dump)"
echo "Make sure to update inc/config.php if you use a database password!"

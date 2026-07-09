#!/bin/bash
# Monitor Script for Absensi Bot System

# Ensure script is run as root for log access
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo). Exiting."
  exit_script=1
fi

if [ -z "$exit_script" ]; then

PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")

check_service() {
    SERVICE=$1
    if systemctl is-active --quiet $SERVICE; then
        echo -e "[\e[32mOK\e[0m] $SERVICE is running."
    else
        echo -e "[\e[31mFAIL\e[0m] $SERVICE is NOT running!"
    fi
}

check_port_80() {
    if command -v curl &> /dev/null; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
        if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 301 ] || [ "$HTTP_CODE" -eq 302 ]; then
            echo -e "[\e[32mOK\e[0m] Web server responded on port 80 (HTTP $HTTP_CODE)."
        else
            echo -e "[\e[31mWARNING\e[0m] Web server returned HTTP $HTTP_CODE on port 80."
        fi
    else
        echo "Curl not installed. Cannot check port 80."
    fi
}

while true; do
    echo "==============================================="
    echo "   ABSENSI BOT SYSTEM - MONITORING & LOGS      "
    echo "==============================================="
    echo "1. Status Services (Nginx, PHP-FPM, MariaDB)"
    echo "2. View Nginx Access Log (Last 100 lines)"
    echo "3. View Nginx Error Log (Last 100 lines)"
    echo "4. View PHP-FPM Error Log (Last 100 lines)"
    echo "5. View MySQL/MariaDB Error Log"
    echo "6. Test Web Server Response"
    echo "7. Quit"
    echo "==============================================="
    read -p "Select an option [1-7]: " choice

    case $choice in
        1)
            echo "--- Service Status ---"
            check_service nginx
            check_service php${PHP_VER}-fpm
            check_service mariadb
            echo ""
            ;;
        2)
            echo "--- Nginx Access Log ---"
            tail -n 100 /var/log/nginx/access.log
            ;;
        3)
            echo "--- Nginx Error Log ---"
            tail -n 100 /var/log/nginx/error.log
            ;;
        4)
            echo "--- PHP-FPM Error Log ---"
            tail -n 100 /var/log/php${PHP_VER}-fpm.log || echo "PHP log not found at /var/log/php${PHP_VER}-fpm.log"
            ;;
        5)
            echo "--- MariaDB Error Log (Recent) ---"
            if [ -f /var/log/mysql/error.log ]; then
                tail -n 50 /var/log/mysql/error.log
            else
                journalctl -u mariadb --no-pager | tail -n 50
            fi
            echo ""
            ;;
        6)
            echo "--- Testing Local Web Server ---"
            check_port_80
            echo ""
            ;;
        7)
            echo "Exiting."
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done

fi

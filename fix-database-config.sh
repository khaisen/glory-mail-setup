#!/bin/bash
# Script to fix Roundcube database configuration
# Run as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "       FIXING ROUNDCUBE DATABASE CONFIGURATION         "
echo "========================================================="

# Variables
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"
ROUNDCUBE_PATH="/var/www/roundcube"
CONFIG_FILE="$ROUNDCUBE_PATH/config/config.inc.php"

# Generate a new database password
DB_PASSWORD=$(openssl rand -base64 16)

# 1. Check if Roundcube directory exists
if [ ! -d "$ROUNDCUBE_PATH" ]; then
  echo "Error: Roundcube directory not found at $ROUNDCUBE_PATH"
  exit 1
fi

# 2. Check if config directory exists
if [ ! -d "$ROUNDCUBE_PATH/config" ]; then
  echo "Creating config directory..."
  mkdir -p "$ROUNDCUBE_PATH/config"
  chown www-data:www-data "$ROUNDCUBE_PATH/config"
fi

# 3. Backup existing config if it exists
if [ -f "$CONFIG_FILE" ]; then
  echo "Backing up existing configuration..."
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
fi

# 4. Check if MySQL/MariaDB is installed and running
echo "Checking database server..."
if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
  echo "MySQL/MariaDB service is not running. Starting..."
  if systemctl list-unit-files | grep -q mariadb; then
    systemctl start mariadb
  elif systemctl list-unit-files | grep -q mysql; then
    systemctl start mysql
  else
    echo "Error: Neither MariaDB nor MySQL service found"
    exit 1
  fi
fi

# 5. Create/reset Roundcube database
echo "Setting up database..."
mysql -e "CREATE DATABASE IF NOT EXISTS roundcube DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || {
  echo "Failed to create database. Checking if MySQL is working...";
  mysql -e "SHOW DATABASES;" || { echo "MySQL connection failed. Please check MySQL service."; exit 1; }
}

# Drop user if exists and recreate
mysql -e "DROP USER IF EXISTS 'roundcube'@'localhost';"
mysql -e "CREATE USER 'roundcube'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# 6. Test database connection
echo "Testing database connection..."
if mysql -u roundcube -p"$DB_PASSWORD" -e "SHOW TABLES;" roundcube; then
  echo "Database connection successful."
else
  echo "Database connection failed. Please check MySQL configuration."
  exit 1
fi

# 7. Initialize Roundcube database schema
echo "Initializing Roundcube database schema..."
if [ -f "$ROUNDCUBE_PATH/SQL/mysql.initial.sql" ]; then
  mysql -u roundcube -p"$DB_PASSWORD" roundcube < "$ROUNDCUBE_PATH/SQL/mysql.initial.sql" || {
    echo "Failed to initialize database schema.";
    exit 1;
  }
else
  echo "Warning: SQL initialization file not found. Is Roundcube properly installed?"
fi

# 8. Create a new configuration file
echo "Creating new configuration file..."
DES_KEY=$(openssl rand -base64 24)

cat > "$CONFIG_FILE" << EOF
<?php

/*
 +-----------------------------------------------------------------------+
 | Local configuration for the Roundcube Webmail installation.           |
 |                                                                       |
 | This file is part of the Roundcube Webmail client                     |
 | Copyright (C) The Roundcube Dev Team                                  |
 |                                                                       |
 | Licensed under the GNU General Public License version 3 or            |
 | any later version with exceptions for skins & plugins.                |
 | See the README file for a full license statement.                     |
 +-----------------------------------------------------------------------+
*/

$config = array();

// Database connection string (DSN) for read+write operations
// Format (compatible with PEAR MDB2): db_provider://user:password@host/database
// Currently supported db_providers: mysql, pgsql, sqlite, mssql, sqlsrv, oracle
// For examples see http://pear.php.net/manual/en/package.database.mdb2.intro-dsn.php
// NOTE: for SQLite use absolute path (Linux): 'sqlite:////full/path/to/sqlite.db?mode=0646'
//       or (Windows): 'sqlite:///C:/full/path/to/sqlite.db'
$config['db_dsnw'] = 'mysql://roundcube:$DB_PASSWORD@localhost/roundcube';

// The IMAP host chosen to perform the log-in.
// Leave blank to show a textbox at login, give a list of hosts
// to display a pulldown menu or set one host as string.
// Enter hostname with prefix ssl:// to use Implicit TLS, or use
// prefix tls:// to use STARTTLS.
// Supported replacement variables:
// %n - hostname ($_SERVER['SERVER_NAME'])
// %t - hostname without the first part
// %d - domain (http hostname $_SERVER['HTTP_HOST'] without the first part)
// %s - domain name after the '@' from e-mail address provided at login screen
// For example %n = mail.domain.tld, %t = domain.tld
$config['default_host'] = 'localhost';

// SMTP server host (for sending mails).
// Enter hostname with prefix ssl:// to use Implicit TLS, or use
// prefix tls:// to use STARTTLS.
// Supported replacement variables:
// %h - user's IMAP hostname
// %n - hostname ($_SERVER['SERVER_NAME'])
// %t - hostname without the first part
// %d - domain (http hostname $_SERVER['HTTP_HOST'] without the first part)
// %z - IMAP domain (IMAP hostname without the first part)
// For example %n = mail.domain.tld, %t = domain.tld
$config['smtp_server'] = 'localhost';

// SMTP port. Use 25 for cleartext, 465 for Implicit TLS, or 587 for STARTTLS (default)
$config['smtp_port'] = 25;

// SMTP username (if required) if you use %u as the username Roundcube
// will use the current username for login
$config['smtp_user'] = '%u';

// SMTP password (if required) if you use %p as the password Roundcube
// will use the current user's password for login
$config['smtp_pass'] = '%p';

// SMTP AUTH type (DIGEST-MD5, CRAM-MD5, LOGIN, PLAIN or empty to use
// best server supported one)
$config['smtp_auth_type'] = '';

// SMTP HELO host 
// Hostname to give to the remote server for SMTP 'HELO' or 'EHLO' messages 
// Leave this blank and you will get the server variable 'server_name' or 
// localhost if that isn't defined. 
$config['smtp_helo_host'] = '$MAIL_HOSTNAME';

// provide an URL where a user can get support for this Roundcube installation
// PLEASE DO NOT LINK TO THE ROUNDCUBE.NET WEBSITE HERE!
$config['support_url'] = '';

// this key is used to encrypt the users imap password which is stored
// in the session record (and the client cookie if remember password is enabled).
// please provide a string of exactly 24 chars.
// YOUR KEY MUST BE DIFFERENT THAN THE SAMPLE VALUE FOR SECURITY REASONS
$config['des_key'] = '$DES_KEY';

// List of active plugins (in plugins/ directory)
$config['plugins'] = array(
    'archive',
    'zipdownload',
);

// skin name: folder from skins/
$config['skin'] = 'elastic';

$config['product_name'] = 'Glory Education Center Webmail';

$config['debug_level'] = 1;

$config['log_driver'] = 'file';
$config['log_dir'] = '/var/log/roundcube/';

return $config;
EOF

# 9. Set proper permissions
echo "Setting proper permissions..."
chown www-data:www-data "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

# 10. Create log directory
echo "Creating log directory..."
mkdir -p /var/log/roundcube/
chown www-data:www-data /var/log/roundcube/
chmod 750 /var/log/roundcube/

# 11. Restart services
echo "Restarting services..."
systemctl restart apache2

echo "\n========================================================="
echo "            DATABASE CONFIGURATION FIXED              "
echo "========================================================="
echo "\nRoundcube database has been reconfigured with fresh settings."
echo "Database: roundcube"
echo "Username: roundcube"
echo "Password: $DB_PASSWORD"
echo "\nThe configuration file has been updated at: $CONFIG_FILE"
echo "\nPlease try accessing your webmail again at: https://$MAIL_HOSTNAME"
echo "If you still have issues, access the diagnostic page: https://$MAIL_HOSTNAME/simple-check.php"
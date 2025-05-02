#!/bin/bash
# Script to install Roundcube from scratch
# Run as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "           FRESH ROUNDCUBE INSTALLATION                "
echo "========================================================="

# Variables
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"
APACHE_ROOT="/var/www/html"
ROUNDCUBE_VERSION="1.6.4"
DB_PASSWORD=$(openssl rand -base64 16)

# 1. Install required packages
echo "\n[1] Installing required packages..."
apt update
apt install -y apache2 php php-fpm php-common php-imap php-json php-curl php-zip php-xml \
               php-mbstring php-imagick php-mysql php-intl php-gd libapache2-mod-php \
               php-pdo php-pdo-mysql php-cli wget unzip mariadb-server

# 2. Create and configure database
echo "\n[2] Setting up database..."

# Start MySQL if not running
systemctl start mariadb || systemctl start mysql

# Create database and user
mysql -e "CREATE DATABASE IF NOT EXISTS roundcube DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "DROP USER IF EXISTS 'roundcube'@'localhost';"
mysql -e "CREATE USER 'roundcube'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# 3. Download and extract Roundcube
echo "\n[3] Downloading and installing Roundcube..."
cd /tmp

# Remove existing installation if any
if [ -d "$APACHE_ROOT/roundcube" ]; then
  echo "Removing existing Roundcube installation..."
  rm -rf "$APACHE_ROOT/roundcube"
fi

# Download Roundcube
wget -O roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/$ROUNDCUBE_VERSION/roundcubemail-$ROUNDCUBE_VERSION-complete.tar.gz

# Extract and move to web root
tar -xzf roundcube.tar.gz
mv roundcubemail-$ROUNDCUBE_VERSION "$APACHE_ROOT/roundcube"

# Create required directories with proper permissions
mkdir -p "$APACHE_ROOT/roundcube/temp"
mkdir -p "$APACHE_ROOT/roundcube/logs"
chown -R www-data:www-data "$APACHE_ROOT/roundcube"
chmod -R 755 "$APACHE_ROOT/roundcube"
chmod -R 777 "$APACHE_ROOT/roundcube/temp"
chmod -R 777 "$APACHE_ROOT/roundcube/logs"

# 4. Initialize database
echo "\n[4] Initializing Roundcube database..."
mysql roundcube < "$APACHE_ROOT/roundcube/SQL/mysql.initial.sql"

# 5. Create configuration file
echo "\n[5] Creating Roundcube configuration..."
DES_KEY=$(openssl rand -base64 24)

cat > "$APACHE_ROOT/roundcube/config/config.inc.php" << EOF
<?php
// Roundcube configuration file

\$config = array();

// Database connection string (DSN) for read+write operations
\$config['db_dsnw'] = 'mysql://roundcube:$DB_PASSWORD@localhost/roundcube';

// The IMAP host chosen to perform the log-in
\$config['default_host'] = 'localhost';

// SMTP server host
\$config['smtp_server'] = 'localhost';
\$config['smtp_port'] = 25;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';

// This key is used to encrypt the users imap password
\$config['des_key'] = '$DES_KEY';

// Enabling file upload
\$config['temp_dir'] = '$APACHE_ROOT/roundcube/temp/';
\$config['log_dir'] = '$APACHE_ROOT/roundcube/logs/';

// List of active plugins
\$config['plugins'] = array('archive', 'zipdownload');

// User interface settings
\$config['skin'] = 'elastic';
\$config['product_name'] = 'Glory Education Center Webmail';

// Debugging options
\$config['debug_level'] = 1;
\$config['log_driver'] = 'file';
\$config['display_errors'] = false;

return \$config;
EOF

chown www-data:www-data "$APACHE_ROOT/roundcube/config/config.inc.php"
chmod 640 "$APACHE_ROOT/roundcube/config/config.inc.php"

# 6. Configure Apache
echo "\n[6] Configuring Apache virtual host..."
cat > "/etc/apache2/sites-available/roundcube.conf" << EOF
<VirtualHost *:80>
    ServerName $MAIL_HOSTNAME
    DocumentRoot $APACHE_ROOT/roundcube
    
    <Directory $APACHE_ROOT/roundcube>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
</VirtualHost>
EOF

# Enable the site and required modules
a2ensite roundcube.conf
a2enmod rewrite

# 7. Create a test file
echo "\n[7] Creating test files..."
cat > "$APACHE_ROOT/roundcube/info.php" << EOF
<?php
phpinfo();
EOF

cat > "$APACHE_ROOT/roundcube/db-test.php" << EOF
<?php
// Test database connection
try {
    \$mysqli = new mysqli('localhost', 'roundcube', '$DB_PASSWORD', 'roundcube');
    
    if (\$mysqli->connect_error) {
        echo "<h1>Connection failed</h1>";
        echo "<p>Error: " . \$mysqli->connect_error . "</p>";
    } else {
        echo "<h1>Database Connection Successful!</h1>";
        echo "<p>Connected to MySQL server version: " . \$mysqli->server_info . "</p>";
        
        // Show tables
        \$result = \$mysqli->query("SHOW TABLES");
        echo "<h2>Tables in database:</h2>";
        echo "<ul>";
        while (\$row = \$result->fetch_array()) {
            echo "<li>" . \$row[0] . "</li>";
        }
        echo "</ul>";
        
        \$mysqli->close();
    }
} catch (Exception \$e) {
    echo "<h1>Exception occurred</h1>";
    echo "<p>" . \$e->getMessage() . "</p>";
}
EOF

chown www-data:www-data "$APACHE_ROOT/roundcube/info.php" "$APACHE_ROOT/roundcube/db-test.php"
chmod 644 "$APACHE_ROOT/roundcube/info.php" "$APACHE_ROOT/roundcube/db-test.php"

# 8. Restart services
echo "\n[8] Restarting services..."
systemctl restart php*-fpm
systemctl restart apache2

# 9. Create a subdomain DNS reminder
CERTS_DIR="/etc/cloudflare/certs"
echo "\n[9] Checking certificate files..."
if [ -d "$CERTS_DIR" ] && [ -f "$CERTS_DIR/origin-certificate.pem" ] && [ -f "$CERTS_DIR/private-key.pem" ]; then
    echo "SSL certificates found. Creating HTTPS configuration..."
    
    cat > "/etc/apache2/sites-available/roundcube-ssl.conf" << EOF
<VirtualHost *:443>
    ServerName $MAIL_HOSTNAME
    DocumentRoot $APACHE_ROOT/roundcube
    
    SSLEngine on
    SSLCertificateFile $CERTS_DIR/origin-certificate.pem
    SSLCertificateKeyFile $CERTS_DIR/private-key.pem
    
    <Directory $APACHE_ROOT/roundcube>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
</VirtualHost>
EOF
    
    a2enmod ssl
    a2ensite roundcube-ssl.conf
    systemctl restart apache2
fi

echo "\n========================================================="
echo "             ROUNDCUBE INSTALLATION COMPLETE          "
echo "========================================================="
echo "\nRoundcube webmail has been installed to $APACHE_ROOT/roundcube"  
echo "Database: roundcube"  
echo "Username: roundcube"  
echo "Password: $DB_PASSWORD"  
echo "\nTest URLs:"  
echo "1. http://$MAIL_HOSTNAME/info.php"  
echo "2. http://$MAIL_HOSTNAME/db-test.php"  
echo "3. http://$MAIL_HOSTNAME  (Main Roundcube interface)"  
echo "\nIf you have SSL certificates configured, you can also access:"  
echo "1. https://$MAIL_HOSTNAME"  
echo "\nEnsure your DNS has an entry for: $MAIL_HOSTNAME"
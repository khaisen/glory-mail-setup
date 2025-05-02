#!/bin/bash
# Final script to fix remaining Roundcube issues
# Run as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "       FIXING FINAL ROUNDCUBE CONFIGURATION ISSUES    "
echo "========================================================="

# Variables
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"
ROUNDCUBE_PATH="/var/www/roundcube"
CONFIG_FILE="$ROUNDCUBE_PATH/config/config.inc.php"

# 1. Install missing MySQL module
echo "\n[1] Installing missing PHP MySQL module..."
apt update

# Detect PHP version
PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
echo "Detected PHP version: $PHP_VERSION"

# Install the appropriate module for the detected version
if [[ "$PHP_VERSION" == "8.1" ]]; then
    apt install -y php8.1-mysql
    echo "Installed php8.1-mysql module"
elif [[ "$PHP_VERSION" == "8.0" ]]; then
    apt install -y php8.0-mysql
    echo "Installed php8.0-mysql module"
elif [[ "$PHP_VERSION" == "7.4" ]]; then
    apt install -y php7.4-mysql
    echo "Installed php7.4-mysql module"
else
    # Generic fallback
    apt install -y php-mysql
    echo "Installed generic php-mysql module"
fi

# 2. Create a corrected configuration file
echo "\n[2] Creating properly formatted configuration file..."

# Generate a database password
DB_PASSWORD=$(openssl rand -base64 16)

# Update database user password
echo "Setting up database user with new password..."
mysql -e "ALTER USER 'roundcube'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "FLUSH PRIVILEGES;"

# Generate a DES key
DES_KEY=$(openssl rand -base64 24)

# Create a new configuration file with proper format
echo "Creating new configuration file..."
cat > "$CONFIG_FILE" << EOF
<?php
// Roundcube configuration

$config = array();

// Database connection
$config['db_dsnw'] = 'mysql://roundcube:$DB_PASSWORD@localhost/roundcube';

// IMAP settings
$config['default_host'] = 'localhost';

// SMTP settings
$config['smtp_server'] = 'localhost';
$config['smtp_port'] = 25;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';

// Interface settings
$config['des_key'] = '$DES_KEY';
$config['product_name'] = 'Glory Education Center Webmail';
$config['skin'] = 'elastic';

// Storage and temp directories
$config['temp_dir'] = '$ROUNDCUBE_PATH/temp/';
$config['log_dir'] = '/var/log/roundcube/';

// Debug settings
$config['debug_level'] = 1;
$config['log_driver'] = 'file';

// Plugins
$config['plugins'] = array('archive', 'zipdownload');

return $config;
EOF

# Set proper permissions
chown www-data:www-data "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

# 3. Create a PHP info file to check modules
echo "\n[3] Creating PHP info file to verify modules..."
cat > "$ROUNDCUBE_PATH/phpinfo.php" << EOF
<?php
phpinfo();
EOF

chown www-data:www-data "$ROUNDCUBE_PATH/phpinfo.php"
chmod 644 "$ROUNDCUBE_PATH/phpinfo.php"

# 4. Verify database is properly set up
echo "\n[4] Verifying database setup..."

# Check if database exists
if mysql -e "USE roundcube;" 2>/dev/null; then
    echo "Roundcube database exists."
    
    # Check if tables exist
    TABLE_COUNT=$(mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'roundcube';" | grep -v "COUNT" | tr -d " \t\n\r")
    
    if [ "$TABLE_COUNT" -gt 0 ]; then
        echo "Database has $TABLE_COUNT tables."
    else
        echo "Database exists but has no tables. Initializing schema..."
        if [ -f "$ROUNDCUBE_PATH/SQL/mysql.initial.sql" ]; then
            mysql roundcube < "$ROUNDCUBE_PATH/SQL/mysql.initial.sql"
            echo "Schema initialized."
        else
            echo "ERROR: Could not find SQL initialization file."
        fi
    fi
else
    echo "Creating roundcube database..."
    mysql -e "CREATE DATABASE roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Initialize schema
    if [ -f "$ROUNDCUBE_PATH/SQL/mysql.initial.sql" ]; then
        mysql roundcube < "$ROUNDCUBE_PATH/SQL/mysql.initial.sql"
        echo "Schema initialized."
    else
        echo "ERROR: Could not find SQL initialization file."
    fi
fi

# 5. Restart services
echo "\n[5] Restarting services..."
systemctl restart php*-fpm
systemctl restart apache2

# 6. Create simple database test file
echo "\n[6] Creating database test file..."
cat > "$ROUNDCUBE_PATH/db-connect.php" << EOF
<?php
// Simple database connection test
try {
    // Connect to database using PDO
    $dsn = 'mysql:host=localhost;dbname=roundcube';
    $user = 'roundcube';
    $password = '$DB_PASSWORD';
    
    echo "<h1>Database Connection Test</h1>";
    echo "<p>Attempting to connect to MySQL using:</p>";
    echo "<ul>";
    echo "<li>DSN: $dsn</li>";
    echo "<li>Username: $user</li>";
    echo "<li>Password: (hidden)</li>";
    echo "</ul>";
    
    $dbh = new PDO($dsn, $user, $password);
    $dbh->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    echo "<p style='color:green'>Connection successful!</p>";
    
    // Test query
    $stmt = $dbh->query('SHOW TABLES');
    $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    echo "<p>Tables in database:</p>";
    echo "<ul>";
    foreach ($tables as $table) {
        echo "<li>$table</li>";
    }
    echo "</ul>";
    
    $dbh = null; // Close connection
} catch (PDOException $e) {
    echo "<p style='color:red'>Connection failed: " . $e->getMessage() . "</p>";
}
?>
EOF

chown www-data:www-data "$ROUNDCUBE_PATH/db-connect.php"
chmod 644 "$ROUNDCUBE_PATH/db-connect.php"

echo "\n========================================================="
echo "                  FIXES COMPLETED                    "
echo "========================================================="
echo "\nFinal fixes for Roundcube have been applied."  
echo "\nPlease check the following URLs to verify everything is working:"  
echo "1. https://$MAIL_HOSTNAME/phpinfo.php  (Check that mysql module is loaded)"  
echo "2. https://$MAIL_HOSTNAME/db-connect.php  (Test database connection)"  
echo "3. https://$MAIL_HOSTNAME/test-rc.php  (Test Roundcube functionality)"  
echo "\nOnce these tests pass, access your webmail at:"  
echo "https://$MAIL_HOSTNAME"
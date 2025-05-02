#!/bin/bash
# Script to specifically fix PHP MySQL module issues
# Run as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "           FIXING PHP MYSQL MODULE ISSUES              "
echo "========================================================="

# 1. Detect PHP version and environment
echo "\n[1] Detecting PHP environment..."
PHP_VERSION=$(php -v | head -n1 | grep -oP 'PHP \K[0-9]\.[0-9]' || echo "unknown")
PHP_FULL_VERSION=$(php -v | head -n1)
PHP_CLI=$(which php)
PHP_ERROR_LOG=$(php -i | grep error_log | grep -v PHP | head -1 | awk '{print $3}')

echo "PHP Version: $PHP_VERSION"
echo "Full version info: $PHP_FULL_VERSION"
echo "PHP CLI Path: $PHP_CLI"
echo "PHP Error Log: $PHP_ERROR_LOG"

# Check what PHP SAPI is used in Apache
APACHE_PHP_HANDLER=""
if apache2ctl -M 2>/dev/null | grep -q "php"; then
    if apache2ctl -M 2>/dev/null | grep -q "php_module"; then
        APACHE_PHP_HANDLER="mod_php"
    elif apache2ctl -M 2>/dev/null | grep -q "proxy_fcgi"; then
        APACHE_PHP_HANDLER="php-fpm"
    fi
fi
echo "Apache PHP Handler: $APACHE_PHP_HANDLER"

# 2. List currently loaded PHP modules
echo "\n[2] Currently loaded PHP modules:"
php -m

# 3. Find and install all possible MySQL modules for this PHP version
echo "\n[3] Installing all possible PHP MySQL modules..."
apt update

# Install multiple packages to ensure coverage
echo "Installing php$PHP_VERSION-mysql..."
apt install -y php$PHP_VERSION-mysql

echo "Installing php-mysql..."
apt install -y php-mysql

echo "Installing php$PHP_VERSION-mysqli..."
apt install -y php$PHP_VERSION-mysqli

echo "Installing php$PHP_VERSION-mysqlnd..."
apt install -y php$PHP_VERSION-mysqlnd

echo "Installing php$PHP_VERSION-pdo-mysql..."
apt install -y php$PHP_VERSION-pdo-mysql

# 4. Check PHP configuration
echo "\n[4] Checking PHP configuration paths..."

# Find all possible php.ini locations
PHP_CLI_INI=$(php -i | grep 'Loaded Configuration File' | awk '{print $5}')
echo "PHP CLI configuration: $PHP_CLI_INI"

# Check for other possible php.ini locations
POSSIBLE_INI_PATHS=(
  "/etc/php/$PHP_VERSION/apache2/php.ini"
  "/etc/php/$PHP_VERSION/fpm/php.ini"
  "/etc/php/$PHP_VERSION/cli/php.ini"
  "/etc/php.ini"
  "/etc/php/$PHP_VERSION/php.ini"
  "/etc/php/$PHP_VERSION/cgi/php.ini"
)

for INI_PATH in "${POSSIBLE_INI_PATHS[@]}"; do
  if [ -f "$INI_PATH" ]; then
    echo "Found php.ini at: $INI_PATH"
    # Make sure extension loading is enabled
    sed -i 's/^;extension=mysql/extension=mysql/g' "$INI_PATH"
    sed -i 's/^;extension=mysqli/extension=mysqli/g' "$INI_PATH"
    sed -i 's/^;extension=pdo_mysql/extension=pdo_mysql/g' "$INI_PATH"
    
    # Also check extension_dir setting
    EXTENSION_DIR=$(grep -P "^extension_dir\s*=" "$INI_PATH" | awk -F'=' '{print $2}' | tr -d '\" ;')
    if [ -n "$EXTENSION_DIR" ]; then
      echo "Extension directory in $INI_PATH: $EXTENSION_DIR"
      ls -la "$EXTENSION_DIR" | grep -i mysql || echo "No MySQL extensions found in directory"
    fi
  fi
done

# 5. Create a test file that tries multiple MySQL connection methods
echo "\n[5] Creating a test file for MySQL connectivity..."
ROUNDCUBE_PATH="/var/www/roundcube"

cat > "$ROUNDCUBE_PATH/mysql-test.php" << 'EOF'
<?php
// Test script for MySQL connectivity using different methods

echo "<h1>PHP MySQL Connectivity Tests</h1>";
echo "<p>PHP Version: " . phpversion() . "</p>";

// Check loaded modules
echo "<h2>Loaded Extensions:</h2>";
$modules = get_loaded_extensions();
sort($modules);
echo "<ul>";
foreach ($modules as $module) {
    if (strpos($module, 'mysql') !== false || $module == 'PDO') {
        echo "<li><strong style='color:green'>$module</strong></li>";
    }
}
echo "</ul>";

// Test MySQL connection using mysqli
echo "<h2>Testing mysqli connection:</h2>";
if (function_exists('mysqli_connect')) {
    echo "<p>mysqli_connect function exists</p>";
    try {
        $mysqli = @new mysqli('localhost', 'roundcube', 'test_password', 'roundcube');
        if ($mysqli->connect_error) {
            echo "<p style='color:red'>Connection failed: " . $mysqli->connect_error . "</p>";
        } else {
            echo "<p style='color:green'>Connection successful using mysqli!</p>";
            $mysqli->close();
        }
    } catch (Exception $e) {
        echo "<p style='color:red'>Exception: " . $e->getMessage() . "</p>";
    }
} else {
    echo "<p style='color:red'>mysqli_connect function does not exist</p>";
}

// Test MySQL connection using PDO
echo "<h2>Testing PDO connection:</h2>";
if (class_exists('PDO')) {
    echo "<p>PDO class exists</p>";
    try {
        $pdo = new PDO('mysql:host=localhost;dbname=roundcube', 'roundcube', 'test_password');
        echo "<p style='color:green'>Connection successful using PDO!</p>";
        $pdo = null;
    } catch (PDOException $e) {
        echo "<p style='color:red'>Connection failed: " . $e->getMessage() . "</p>";
    }
} else {
    echo "<p style='color:red'>PDO class does not exist</p>";
}

// Show phpinfo
echo "<h2>PHP Info for MySQL-related modules:</h2>";
echo "<div style='height: 300px; overflow: auto; border: 1px solid #ccc; padding: 10px;'>";
$modules = ['mysqli', 'mysqlnd', 'pdo_mysql', 'PDO'];
ob_start();
phpinfo(INFO_MODULES);
$phpinfo = ob_get_clean();

// Extract module sections
$sections = [];
foreach ($modules as $module) {
    if (preg_match("/<h2>.*?$module.*?<\/h2>.*?<table.*?>(.*?)<\/table>/s", $phpinfo, $matches)) {
        echo "<h3>$module</h3>";
        echo "<table>" . $matches[1] . "</table>";
    }
}
echo "</div>";

// Additional diagnostics
echo "<h2>PHP.ini Locations:</h2>";
echo "<p>Loaded php.ini: " . php_ini_loaded_file() . "</p>";
echo "<p>Additional .ini files: " . php_ini_scanned_files() . "</p>";

echo "<h2>Extension Directory:</h2>";
echo "<p>" . ini_get('extension_dir') . "</p>";

echo "<h2>MySQL Server Connection Test:</h2>";
if (function_exists('shell_exec')) {
    $mysqlCheck = shell_exec('mysqladmin ping 2>&1');
    echo "<pre>$mysqlCheck</pre>";
} else {
    echo "<p>Cannot execute shell commands from PHP</p>";
}
EOF

chown www-data:www-data "$ROUNDCUBE_PATH/mysql-test.php"
chmod 644 "$ROUNDCUBE_PATH/mysql-test.php"

# 6. Check MySQL server status
echo "\n[6] Checking MySQL/MariaDB server status..."
systemctl status mysql || systemctl status mariadb

# 7. Restart PHP and web services
echo "\n[7] Restarting PHP and web services..."

# Restart PHP-FPM if it exists
if systemctl list-units --type=service | grep -q "php.*-fpm"; then
    echo "Restarting PHP-FPM..."
    systemctl restart php*-fpm
fi

# Restart Apache
echo "Restarting Apache..."
systemctl restart apache2

# 8. Create simple standalone PHP+MySQL test
echo "\n[8] Creating standalone PHP+MySQL test..."

# Create a test directory outside of Roundcube
TEST_DIR="/var/www/html/test"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/index.php" << 'EOF'
<?php
echo "<h1>Simple PHP MySQL Test</h1>";

// Show basic PHP info
echo "<p>PHP Version: " . phpversion() . "</p>";

// Check for MySQL support
echo "<h2>MySQL Support:</h2>";
echo "<ul>";
echo "<li>mysqli_connect() exists: " . (function_exists('mysqli_connect') ? "Yes" : "No") . "</li>";
echo "<li>PDO exists: " . (class_exists('PDO') ? "Yes" : "No") . "</li>";
echo "<li>mysqlnd loaded: " . (in_array('mysqlnd', get_loaded_extensions()) ? "Yes" : "No") . "</li>";
echo "</ul>";

// List all loaded extensions
echo "<h2>All Loaded Extensions:</h2>";
$extensions = get_loaded_extensions();
sort($extensions);
echo "<ul>";
foreach ($extensions as $ext) {
    echo "<li>$ext</li>";
}
echo "</ul>";

// Try a basic MySQL connection
echo "<h2>Attempt MySQL Connection:</h2>";
try {
    $mysqli = new mysqli('localhost', 'root', '');
    echo "<p>Connected to MySQL server version: " . $mysqli->server_info . "</p>";
    $mysqli->close();
} catch (Exception $e) {
    echo "<p>Error: " . $e->getMessage() . "</p>";
}
EOF

chown www-data:www-data -R "$TEST_DIR"
chmod 755 "$TEST_DIR"
chmod 644 "$TEST_DIR/index.php"

# Create a simple Apache configuration for the test
cat > "/etc/apache2/sites-available/mysql-test.conf" << EOF
<VirtualHost *:80>
    ServerName mysql-test
    DocumentRoot $TEST_DIR
    
    <Directory $TEST_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite mysql-test.conf
systemctl reload apache2

echo "\n========================================================="
echo "                  FIXES COMPLETED                    "
echo "========================================================="
echo "\nPHP MySQL module installation has been attempted using multiple methods."  
echo "\nPlease check these test URLs:"  
echo "1. http://YOUR_SERVER_IP/test/  (Standalone MySQL test)"  
echo "2. https://mail.gloryeducationcenter.in/mysql-test.php  (Detailed MySQL connectivity test)"  
echo "\nAdditional diagnostic information:"  
echo "- The script has installed all possible PHP MySQL modules"  
echo "- PHP configuration files have been checked and updated"  
echo "- Services have been restarted"  
echo "\nIf MySQL modules are still not loading, check these logs:"  
echo "- Apache error log: /var/log/apache2/error.log"  
echo "- PHP error log: $PHP_ERROR_LOG"
#!/bin/bash
# Script to fix Roundcube application errors
# Run as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "        FIXING ROUNDCUBE APPLICATION ERRORS            "
echo "========================================================="

# Variables
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"
ROUNDCUBE_PATH="/var/www/roundcube"

# 1. Check and display Roundcube logs
echo "\n[1] Checking Roundcube logs..."
ROUNDCUBE_LOGS="/var/log/roundcube"
APACHE_LOGS="/var/log/apache2/roundcube_error.log"

if [ -d "$ROUNDCUBE_LOGS" ]; then
    echo "Latest Roundcube log entries:"
    find "$ROUNDCUBE_LOGS" -type f -name "*.log" -exec tail -n 20 {} \;
fi

echo "Latest Apache error log entries:"
tail -n 20 "$APACHE_LOGS" 2>/dev/null || echo "No Apache error logs found"

# 2. Check and create required directories
echo "\n[2] Creating and fixing Roundcube directories..."
REQUIRED_DIRS=("temp" "logs" "config" "plugins" "skins")

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$ROUNDCUBE_PATH/$dir" ]; then
        echo "Creating missing directory: $dir"
        mkdir -p "$ROUNDCUBE_PATH/$dir"
    fi
    
    echo "Setting permissions for directory: $dir"
    chown -R www-data:www-data "$ROUNDCUBE_PATH/$dir"
    
    if [[ "$dir" == "temp" || "$dir" == "logs" ]]; then
        chmod -R 777 "$ROUNDCUBE_PATH/$dir"
    else
        chmod -R 755 "$ROUNDCUBE_PATH/$dir"
    fi
done

# 3. Create dedicated log directory
echo "\n[3] Setting up Roundcube log directory..."
mkdir -p /var/log/roundcube
chown -R www-data:www-data /var/log/roundcube
chmod -R 777 /var/log/roundcube

# 4. Update Roundcube configuration with debug settings
echo "\n[4] Updating Roundcube configuration with debug settings..."
CONFIG_FILE="$ROUNDCUBE_PATH/config/config.inc.php"

if [ -f "$CONFIG_FILE" ]; then
    # Backup current config
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    
    # Check if debug sections exist and add/update them
    if grep -q "debug_level" "$CONFIG_FILE"; then
        sed -i "s/\$config\['debug_level'\] = .*/\$config\['debug_level'\] = 1;/g" "$CONFIG_FILE"
    else
        echo "\$config['debug_level'] = 1;" >> "$CONFIG_FILE"
    fi
    
    if grep -q "log_driver" "$CONFIG_FILE"; then
        sed -i "s/\$config\['log_driver'\] = .*/\$config\['log_driver'\] = 'file';/g" "$CONFIG_FILE"
    else
        echo "\$config['log_driver'] = 'file';" >> "$CONFIG_FILE"
    fi
    
    if grep -q "log_dir" "$CONFIG_FILE"; then
        sed -i "s|\$config\['log_dir'\] = .*|\$config\['log_dir'\] = '/var/log/roundcube/';|g" "$CONFIG_FILE"
    else
        echo "\$config['log_dir'] = '/var/log/roundcube/';" >> "$CONFIG_FILE"
    fi
    
    # Add session directory setting if not present
    if ! grep -q "session_path" "$CONFIG_FILE"; then
        echo "\$config['session_path'] = '$ROUNDCUBE_PATH/temp/';" >> "$CONFIG_FILE"
    fi
    
    # Add temp directory setting if not present
    if ! grep -q "temp_dir" "$CONFIG_FILE"; then
        echo "\$config['temp_dir'] = '$ROUNDCUBE_PATH/temp/';" >> "$CONFIG_FILE"
    fi
    
    # Fix debug mode to catch issues
    if ! grep -q "display_errors" "$CONFIG_FILE"; then
        echo "\$config['display_errors'] = true;" >> "$CONFIG_FILE"
    fi
    
    # Ensure the config file is properly formatted with return statement
    if ! grep -q "return \$config;" "$CONFIG_FILE"; then
        echo "\nreturn \$config;" >> "$CONFIG_FILE"
    fi

    # Set proper permissions on the config file
    chown www-data:www-data "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"
else
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

# 5. Check PHP configuration for Roundcube requirements
echo "\n[5] Checking PHP configuration..."
PHP_VERSION=$(php -v | grep -oE '^PHP [0-9]+\.[0-9]+' | cut -d' ' -f2)
PHP_MAJOR=${PHP_VERSION%%.*}
PHP_MINOR=${PHP_VERSION#*.}

PHP_INI="/etc/php/$PHP_MAJOR.$PHP_MINOR/apache2/php.ini"
if [ ! -f "$PHP_INI" ]; then
    PHP_INI="/etc/php/$PHP_MAJOR.$PHP_MINOR/fpm/php.ini"
fi

if [ -f "$PHP_INI" ]; then
    echo "Updating PHP settings in $PHP_INI"
    
    # Backup the file
    cp "$PHP_INI" "${PHP_INI}.bak"
    
    # Update settings
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 20M/g' "$PHP_INI"
    sed -i 's/^post_max_size = .*/post_max_size = 21M/g' "$PHP_INI"
    sed -i 's/^memory_limit = .*/memory_limit = 128M/g' "$PHP_INI"
    sed -i 's/^display_errors = .*/display_errors = On/g' "$PHP_INI"
    sed -i 's/^error_reporting = .*/error_reporting = E_ALL/g' "$PHP_INI"
    
    echo "PHP settings updated"
else
    echo "ERROR: Could not find PHP configuration file"
fi

# 6. Install additional required PHP modules
echo "\n[6] Installing additional PHP modules..."
apt-get update
apt-get install -y php-gd php-xml php-mbstring php-dom php-fileinfo php-intl php-zip php-pdo-mysql

# 7. Create a completely fresh Roundcube configuration
echo "\n[7] Creating fresh Roundcube configuration..."

# Get database credentials from existing config
DB_PASSWORD=""
if [ -f "$CONFIG_FILE" ]; then
    DB_STRING=$(grep -oP "db_dsnw.*?mysql://\K[^@]*" "$CONFIG_FILE" | head -1)
    if [ -n "$DB_STRING" ]; then
        DB_PASSWORD=$(echo "$DB_STRING" | cut -d':' -f2)
    fi
fi

# Generate a new password if none was found
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(openssl rand -base64 16)
    # Update database user
    mysql -e "ALTER USER 'roundcube'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -e "FLUSH PRIVILEGES;"
fi

# Generate a DES key
DES_KEY=$(openssl rand -base64 24)

# Create a completely fresh config
cat > "$CONFIG_FILE" << EOF
<?php

/*
 +-----------------------------------------------------------------------+
 | Local configuration for the Roundcube Webmail installation.           |
 +-----------------------------------------------------------------------+
*/

$config = array();

// Database connection string (DSN) for read+write operations
$config['db_dsnw'] = 'mysql://roundcube:$DB_PASSWORD@localhost/roundcube';

// The IMAP host chosen to perform the log-in
$config['default_host'] = 'localhost';

// SMTP server host
$config['smtp_server'] = 'localhost';

// SMTP port
$config['smtp_port'] = 25;

// SMTP username
$config['smtp_user'] = '%u';

// SMTP password
$config['smtp_pass'] = '%p';

// Use the current user identity as envelope sender for sent messages
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';

// this key is used to encrypt the users imap password which is stored
// in the session record
$config['des_key'] = '$DES_KEY';

// List of active plugins
$config['plugins'] = array(
    'archive',
    'zipdownload',
);

// skin name: folder from skins/
$config['skin'] = 'elastic';

// Product name shown in the window title
$config['product_name'] = 'Glory Education Center Webmail';

// Temp directory
$config['temp_dir'] = '$ROUNDCUBE_PATH/temp/';

// Session directory
$config['session_path'] = '$ROUNDCUBE_PATH/temp/';

// Logging configuration
$config['log_driver'] = 'file';
$config['log_dir'] = '/var/log/roundcube/';
$config['debug_level'] = 1;
$config['display_errors'] = true;

// Disable auto-completion for the password field
$config['login_autocomplete'] = 2;

// Allow browser-based spellchecking
$config['enable_spellcheck'] = true;

// Make use of the built-in spell checker
$config['spellcheck_engine'] = 'pspell';

// Set identities access level (default: 0)
$config['identities_level'] = 0;

// Use this charset as fallback for message decoding
$config['default_charset'] = 'UTF-8';

return $config;
EOF

# Set proper permissions
chown www-data:www-data "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

# 8. Create a simple test file to verify Roundcube functionality
echo "\n[8] Creating test file for Roundcube functionality..."
cat > "$ROUNDCUBE_PATH/test-rc.php" << 'EOF'
<?php
// Test script for Roundcube functionality

// Display basic info
echo "<h1>Roundcube Test Script</h1>";
echo "<p>PHP Version: " . phpversion() . "</p>";

// Check if Roundcube files are accessible
echo "<h2>Checking Roundcube files:</h2>";
echo "<ul>";
$required_files = array(
    'index.php',
    'program/include/iniset.php',
    'config/config.inc.php'
);

foreach ($required_files as $file) {
    echo "<li>$file: " . (file_exists($file) ? "<span style='color:green'>Found</span>" : "<span style='color:red'>Missing</span>") . "</li>";
}
echo "</ul>";

// Check directories and permissions
echo "<h2>Checking directories and permissions:</h2>";
echo "<ul>";
$required_dirs = array(
    'temp' => 0777,
    'logs' => 0777,
    'plugins' => 0755,
    'skins' => 0755,
    'program' => 0755
);

foreach ($required_dirs as $dir => $perms) {
    $exists = is_dir($dir);
    $writable = is_writable($dir);
    $permission = substr(sprintf('%o', fileperms($dir)), -4);
    
    echo "<li>$dir: " . 
         ($exists ? "<span style='color:green'>Exists</span>" : "<span style='color:red'>Missing</span>") . 
         ($writable ? ", <span style='color:green'>Writable</span>" : ", <span style='color:red'>Not writable</span>") . 
         ", Permissions: $permission" . 
         "</li>";
}
echo "</ul>";

// Try to initialize Roundcube
echo "<h2>Attempting to load Roundcube:</h2>";
try {
    // Try to initialize Roundcube environment
    define('INSTALL_PATH', realpath(dirname(__FILE__)) . '/');
    include_once INSTALL_PATH . 'program/include/iniset.php';
    
    echo "<p style='color:green'>Successfully loaded Roundcube environment</p>";
    
    // Try to get the config
    global $config;
    if (isset($config) && is_array($config)) {
        echo "<p>Configuration loaded successfully</p>";
        
        // Show some important config values (without passwords)
        echo "<h3>Important configuration values:</h3>";
        echo "<ul>";
        $important_configs = array('db_dsnw', 'default_host', 'smtp_server', 'temp_dir', 'log_dir');
        
        foreach ($important_configs as $key) {
            if (isset($config[$key])) {
                $value = $config[$key];
                // Mask password in connection string
                if ($key == 'db_dsnw') {
                    $value = preg_replace('/:[^:]*@/', ':***@', $value);
                }
                echo "<li>$key: $value</li>";
            } else {
                echo "<li>$key: <span style='color:red'>Not set</span></li>";
            }
        }
        echo "</ul>";
    } else {
        echo "<p style='color:red'>Failed to load configuration</p>";
    }
} catch (Exception $e) {
    echo "<p style='color:red'>Error: " . $e->getMessage() . "</p>";
}

// Display PHP modules
echo "<h2>Loaded PHP Modules:</h2>";
echo "<ul>";
$required_modules = array('mysql', 'json', 'session', 'pcre', 'xml', 'dom', 'mbstring');

foreach ($required_modules as $module) {
    $loaded = extension_loaded($module);
    echo "<li>$module: " . ($loaded ? "<span style='color:green'>Loaded</span>" : "<span style='color:red'>Not loaded</span>") . "</li>";
}
echo "</ul>";
EOF

# Set proper permissions
chown www-data:www-data "$ROUNDCUBE_PATH/test-rc.php"
chmod 644 "$ROUNDCUBE_PATH/test-rc.php"

# 9. Restart services
echo "\n[9] Restarting services..."
systemctl restart php*-fpm || true
systemctl restart apache2

echo "\n========================================================="
echo "                  FIXES COMPLETED                    "
echo "========================================================="
echo "\nRoundcube application errors should now be fixed."  
echo "\nDiagnostic URLs to check:"  
echo "1. https://$MAIL_HOSTNAME/test-rc.php  (Detailed Roundcube test)"  
echo "\nAfter verifying everything is working, try accessing your webmail:"  
echo "https://$MAIL_HOSTNAME"  
echo "\nLog locations for troubleshooting:"  
echo "- Apache logs: $APACHE_LOGS"  
echo "- Roundcube logs: $ROUNDCUBE_LOGS/*"
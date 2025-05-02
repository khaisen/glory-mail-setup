#!/bin/bash
# Script to fix common PHP and webmail issues
# Run as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "       FIXING PHP AND WEBMAIL CONFIGURATION            "
echo "========================================================="

# Variables
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"
ROUNDCUBE_PATH="/var/www/roundcube"

# 1. Install/reinstall required PHP modules
echo "\n[1] Installing/reinstalling required PHP modules..."
apt update
apt install -y php php-common php-imap php-json php-curl php-zip php-xml \
              php-mbstring php-imagick php-mysql php-intl php-cli \
              libapache2-mod-php

# 2. Check and fix Apache PHP configuration
echo "\n[2] Checking Apache PHP configuration..."

# Make sure PHP is enabled in Apache
if ! a2query -m php > /dev/null 2>&1; then
    echo "Enabling PHP module in Apache..."
    a2enmod php > /dev/null 2>&1
    RESTART_APACHE=true
fi

# Create a test PHP file
echo "Creating simple PHP test file..."
cat > "$ROUNDCUBE_PATH/test.php" << 'EOF'
<?php
  echo "PHP is working correctly.";
  phpinfo();
?>
EOF

chown www-data:www-data "$ROUNDCUBE_PATH/test.php"
chmod 644 "$ROUNDCUBE_PATH/test.php"

# Copy our simple diagnostic script
echo "Copying diagnostic script..."
if [ -f "./simple-check.php" ]; then
    cp ./simple-check.php "$ROUNDCUBE_PATH/"
    chown www-data:www-data "$ROUNDCUBE_PATH/simple-check.php"
    chmod 644 "$ROUNDCUBE_PATH/simple-check.php"
    echo "Diagnostic script installed at: https://$MAIL_HOSTNAME/simple-check.php"
else
    echo "Warning: simple-check.php not found in the current directory"
fi

# 3. Check and fix permissions for Roundcube files
echo "\n[3] Fixing Roundcube permissions..."
if [ -d "$ROUNDCUBE_PATH" ]; then
    echo "Setting correct ownership for Roundcube files..."
    chown -R www-data:www-data "$ROUNDCUBE_PATH"
    
    echo "Setting correct permissions for Roundcube directories..."
    find "$ROUNDCUBE_PATH" -type d -exec chmod 755 {} \;
    
    echo "Setting correct permissions for Roundcube files..."
    find "$ROUNDCUBE_PATH" -type f -exec chmod 644 {} \;
    
    # Special permissions for specific directories
    if [ -d "$ROUNDCUBE_PATH/temp" ]; then
        echo "Setting permissions for temp directory..."
        chmod -R 777 "$ROUNDCUBE_PATH/temp"
    fi
    
    if [ -d "$ROUNDCUBE_PATH/logs" ]; then
        echo "Setting permissions for logs directory..."
        chmod -R 777 "$ROUNDCUBE_PATH/logs"
    fi
else
    echo "Error: Roundcube directory not found at $ROUNDCUBE_PATH"
fi

# 4. Check and fix Apache configuration
echo "\n[4] Checking Apache configuration..."

# Make sure the site is enabled
if [ ! -f "/etc/apache2/sites-enabled/$MAIL_HOSTNAME.conf" ]; then
    echo "Enabling $MAIL_HOSTNAME site..."
    a2ensite "$MAIL_HOSTNAME.conf"
    RESTART_APACHE=true
fi

# Make sure necessary Apache modules are enabled
for module in rewrite ssl php7.4 mime; do
    if ! a2query -m $module > /dev/null 2>&1; then
        echo "Enabling Apache module: $module"
        a2enmod $module > /dev/null 2>&1
        RESTART_APACHE=true
    fi
done

# Check if default site is disabled
if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
    echo "Disabling default Apache site..."
    a2dissite 000-default.conf
    RESTART_APACHE=true
fi

# 5. Fix Apache virtual host configuration
echo "\n[5] Updating Apache virtual host configuration..."
if [ -f "/etc/apache2/sites-available/$MAIL_HOSTNAME.conf" ]; then
    echo "Backing up current configuration..."
    cp "/etc/apache2/sites-available/$MAIL_HOSTNAME.conf" "/etc/apache2/sites-available/$MAIL_HOSTNAME.conf.bak"
    
    echo "Creating updated configuration with PHP handling..."
    cat > "/etc/apache2/sites-available/$MAIL_HOSTNAME.conf" << EOF
<VirtualHost *:80>
    ServerName $MAIL_HOSTNAME
    DocumentRoot $ROUNDCUBE_PATH
    
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/\$1 [R,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName $MAIL_HOSTNAME
    DocumentRoot $ROUNDCUBE_PATH
    
    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
    
    SSLEngine on
    SSLCertificateFile /etc/cloudflare/certs/origin-certificate.pem
    SSLCertificateKeyFile /etc/cloudflare/certs/private-key.pem
    
    <Directory $ROUNDCUBE_PATH>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        
        <FilesMatch \\.php$>
            SetHandler application/x-httpd-php
        </FilesMatch>
    </Directory>
    
    # PHP specific settings
    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>
    
    # Deny access to .git, .htaccess, etc
    <DirectoryMatch "\.(git|svn)/">
        Deny from all
    </DirectoryMatch>
    
    <FilesMatch "^\.ht">
        Deny from all
    </FilesMatch>
</VirtualHost>
EOF
    RESTART_APACHE=true
else
    echo "Error: Virtual host configuration file not found"
fi

# 6. Restart Apache if needed
if [ "$RESTART_APACHE" = true ]; then
    echo "\n[6] Restarting Apache..."
    systemctl restart apache2
fi

echo "\n[7] Checking Apache status..."
systemctl status apache2 --no-pager

echo "\n========================================================="
echo "                 FIXES COMPLETED                     "
echo "========================================================="
echo "\nPlease check the following URLs to verify PHP is working:\n"
echo "1. https://$MAIL_HOSTNAME/test.php"
echo "2. https://$MAIL_HOSTNAME/simple-check.php"
echo "\nIf these work but Roundcube still doesn't, check the diagnostic output"}}
]
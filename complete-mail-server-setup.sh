#!/bin/bash
# Complete Mail Server Setup for gloryeducationcenter.in
# This script performs a full installation and configuration of a mail server

# Exit on error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Variables - customize these before running
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"
ADMIN_EMAIL="admin@$DOMAIN"
SERVER_IP="YOUR_SERVER_IP" # Replace with your actual server IP
CERTS_DIR="/etc/cloudflare/certs"
CERT_FOLDER="./certificates" # Local folder containing your Cloudflare certificates

echo "========================================================="
echo "       COMPLETE MAIL SERVER SETUP SCRIPT               "
echo "========================================================="
echo "Domain: $DOMAIN"
echo "Mail Hostname: $MAIL_HOSTNAME"
echo "Admin Email: $ADMIN_EMAIL"
echo "Server IP: $SERVER_IP"
echo "Certificate Directory: $CERTS_DIR"
echo ""

# Prompt for admin password
read -s -p "Enter password for $ADMIN_EMAIL: " ADMIN_PASSWORD
echo ""
if [ -z "$ADMIN_PASSWORD" ]; then
  echo "Password cannot be empty"
  exit 1
fi

read -s -p "Confirm password: " CONFIRM_PASSWORD
echo ""
if [ "$ADMIN_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
  echo "Passwords do not match"
  exit 1
fi

# Generate a strong database password
DB_PASSWORD=$(openssl rand -base64 16)

# Check if certificate folder exists
if [ ! -d "$CERT_FOLDER" ]; then
  echo "ERROR: Certificate folder '$CERT_FOLDER' not found"
  echo "Please create this folder and place your Cloudflare origin-certificate.pem and private-key.pem files inside"
  exit 1
fi

if [ ! -f "$CERT_FOLDER/origin-certificate.pem" ] || [ ! -f "$CERT_FOLDER/private-key.pem" ]; then
  echo "ERROR: Certificate files not found in '$CERT_FOLDER'"
  echo "Please ensure origin-certificate.pem and private-key.pem exist in this folder"
  exit 1
fi

# STEP 1: System preparation
echo "\n[STEP 1] System preparation and package installation"

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y curl wget gnupg2 ca-certificates lsb-release apt-transport-https dnsutils netcat telnet
apt install -y postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd postfix-mysql dovecot-mysql
apt install -y apache2 php php-common php-imap php-json php-curl php-zip php-xml php-mbstring php-imagick php-mysql php-intl mariadb-server
apt install -y fail2ban opendkim opendkim-tools postfix-policyd-spf-python openssl

# Set hostname
echo "Setting hostname to $MAIL_HOSTNAME..."
hostnamectl set-hostname $MAIL_HOSTNAME

# Update hosts file
echo "Updating /etc/hosts file..."
if ! grep -q "$MAIL_HOSTNAME" /etc/hosts; then
  echo "127.0.1.1 $MAIL_HOSTNAME mail" >> /etc/hosts
fi

# Configure Firewall
echo "Setting up firewall..."
apt install -y ufw
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 25/tcp   # SMTP
ufw allow 465/tcp  # SMTPS
ufw allow 587/tcp  # Submission
ufw allow 110/tcp  # POP3
ufw allow 995/tcp  # POP3S
ufw allow 143/tcp  # IMAP
ufw allow 993/tcp  # IMAPS

# Only enable UFW if it's not already enabled, to prevent SSH lockout
if ! ufw status | grep -q "Status: active"; then
  echo "Enabling firewall..."
  ufw --force enable
fi

# STEP 2: Mail directory setup
echo "\n[STEP 2] Setting up mail directories"

# Create mail directories and user
echo "Creating mail directories and virtual user..."
mkdir -p /var/mail/vhosts/$DOMAIN

# Create vmail user and group if they don't exist
if ! getent group vmail >/dev/null; then
  groupadd -g 5000 vmail
fi

if ! getent passwd vmail >/dev/null; then
  useradd -g vmail -u 5000 -d /var/mail/vhosts -s /usr/sbin/nologin vmail
fi

chown -R vmail:vmail /var/mail/vhosts

# STEP 3: SSL Certificates setup
echo "\n[STEP 3] Setting up SSL certificates"

# Create certificate directory
echo "Creating certificate directory..."
mkdir -p $CERTS_DIR

# Copy certificate files
echo "Copying certificate files..."
cp "$CERT_FOLDER/origin-certificate.pem" "$CERTS_DIR/"
cp "$CERT_FOLDER/private-key.pem" "$CERTS_DIR/"

# Set proper permissions
echo "Setting proper certificate permissions..."
chown root:root $CERTS_DIR/origin-certificate.pem
chmod 644 $CERTS_DIR/origin-certificate.pem
chown root:root $CERTS_DIR/private-key.pem
chmod 640 $CERTS_DIR/private-key.pem

# STEP 4: Postfix configuration
echo "\n[STEP 4] Configuring Postfix"

# Backup original configuration if it exists
if [ -f /etc/postfix/main.cf ]; then
  cp /etc/postfix/main.cf /etc/postfix/main.cf.bak
fi

# Create main Postfix configuration
echo "Creating Postfix main configuration..."
cat > /etc/postfix/main.cf << EOF
# Basic Configuration
smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file = $CERTS_DIR/origin-certificate.pem
smtpd_tls_key_file = $CERTS_DIR/private-key.pem
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtp_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtp_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1

# Network settings
myhostname = $MAIL_HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
inet_interfaces = all
inet_protocols = ipv4
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
relayhost = 
mailbox_size_limit = 0
recipient_delimiter = +
smtpd_sasl_local_domain = \$myhostname
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination

# Virtual domains, users, and aliases
virtual_mailbox_domains = \$mydomain
virtual_mailbox_base = /var/mail/vhosts
virtual_mailbox_maps = hash:/etc/postfix/vmailbox
virtual_alias_maps = hash:/etc/postfix/virtual
virtual_minimum_uid = 100
virtual_uid_maps = static:5000
virtual_gid_maps = static:5000

# SMTP restrictions to prevent spam
smtpd_helo_required = yes
smtpd_helo_restrictions = 
    permit_mynetworks, 
    permit_sasl_authenticated, 
    reject_non_fqdn_helo_hostname, 
    reject_invalid_helo_hostname
smtpd_recipient_restrictions = 
    permit_mynetworks, 
    permit_sasl_authenticated, 
    reject_non_fqdn_recipient, 
    reject_unknown_recipient_domain, 
    reject_unlisted_recipient, 
    reject_unauth_destination
smtpd_sender_restrictions = 
    permit_mynetworks, 
    permit_sasl_authenticated, 
    reject_non_fqdn_sender, 
    reject_unknown_sender_domain
EOF

# Create virtual mailbox and alias files
echo "Configuring virtual mailboxes and aliases..."
echo "$ADMIN_EMAIL $DOMAIN/admin/" > /etc/postfix/vmailbox
echo "@$DOMAIN $ADMIN_EMAIL" > /etc/postfix/virtual

# Generate lookup tables
postmap /etc/postfix/vmailbox
postmap /etc/postfix/virtual

# Configure master.cf file
echo "Configuring Postfix master file..."
sed -i 's/#submission/submission/g' /etc/postfix/master.cf
sed -i 's/#smtps/smtps/g' /etc/postfix/master.cf

# STEP 5: Dovecot configuration
echo "\n[STEP 5] Configuring Dovecot"

# Configure Dovecot
echo "Configuring Dovecot main settings..."
sed -i 's/^#protocols = imap pop3 lmtp/protocols = imap pop3 lmtp/g' /etc/dovecot/dovecot.conf

# Configure mail location
echo "Configuring mail location..."
sed -i 's/^mail_location = .*/mail_location = maildir:\/var\/mail\/vhosts\/%d\/%n/g' /etc/dovecot/conf.d/10-mail.conf
echo "mail_privileged_group = vmail" >> /etc/dovecot/conf.d/10-mail.conf

# Configure authentication
echo "Configuring authentication settings..."
sed -i 's/^auth_mechanisms = .*/auth_mechanisms = plain login/g' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#!include auth-system.conf.ext/!include auth-system.conf.ext\n#!include auth-sql.conf.ext\n#!include auth-ldap.conf.ext\n#!include auth-passwdfile.conf.ext\n!include auth-static.conf.ext/g' /etc/dovecot/conf.d/10-auth.conf

# Create static authentication configuration
echo "Creating static authentication config..."
cat > /etc/dovecot/conf.d/auth-static.conf.ext << EOF
passdb {
  driver = passwd-file
  args = scheme=SHA512-CRYPT /etc/dovecot/users
}

userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOF

# Configure SSL settings
echo "Configuring SSL settings..."
cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = required
ssl_cert = <$CERTS_DIR/origin-certificate.pem
ssl_key = <$CERTS_DIR/private-key.pem
ssl_min_protocol = TLSv1.2
ssl_prefer_server_ciphers = yes
EOF

# Configure master settings for Postfix integration
echo "Configuring master settings..."
sed -i '/unix_listener auth-userdb {/,/}/c\  unix_listener auth-userdb {\n    mode = 0600\n    user = vmail\n  }' /etc/dovecot/conf.d/10-master.conf
sed -i '/# Postfix smtp-auth/,/}/c\  # Postfix smtp-auth\n  unix_listener \/var\/spool\/postfix\/private\/auth {\n    mode = 0666\n    user = postfix\n    group = postfix\n  }' /etc/dovecot/conf.d/10-master.conf

# Create admin user
echo "Creating admin mail user..."
mkdir -p /var/mail/vhosts/$DOMAIN/admin/{cur,new,tmp}
chown -R vmail:vmail /var/mail/vhosts/$DOMAIN

# Generate password hash for Dovecot
echo "Generating password hash..."
DOVECOT_PASS=$(doveadm pw -s SHA512-CRYPT -p "$ADMIN_PASSWORD")
echo "$ADMIN_EMAIL:$DOVECOT_PASS" > /etc/dovecot/users

# Set proper permissions
chmod 600 /etc/dovecot/users
chown vmail:dovecot /etc/dovecot/users

# STEP 6: Apache and Roundcube setup
echo "\n[STEP 6] Setting up Apache and Roundcube webmail"

# Disable default site
echo "Disabling default Apache site..."
a2dissite 000-default.conf

# Configure Apache virtual host
echo "Creating Apache virtual host configuration..."
cat > /etc/apache2/sites-available/$MAIL_HOSTNAME.conf << EOF
<VirtualHost *:80>
    ServerName $MAIL_HOSTNAME
    DocumentRoot /var/www/roundcube
    
    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/\$1 [R,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName $MAIL_HOSTNAME
    DocumentRoot /var/www/roundcube
    
    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
    
    SSLEngine on
    SSLCertificateFile $CERTS_DIR/origin-certificate.pem
    SSLCertificateKeyFile $CERTS_DIR/private-key.pem
    
    <Directory /var/www/roundcube>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Enable site and required modules
echo "Enabling Apache site and modules..."
a2ensite $MAIL_HOSTNAME.conf
a2enmod rewrite ssl

# Configure MySQL database for Roundcube
echo "Setting up MySQL database for Roundcube..."
mysql -e "CREATE DATABASE IF NOT EXISTS roundcube DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -e "GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "FLUSH PRIVILEGES;"

# Download and install Roundcube
echo "Installing Roundcube webmail..."
cd /tmp
wget https://github.com/roundcube/roundcubemail/releases/download/1.6.4/roundcubemail-1.6.4-complete.tar.gz
tar -xvf roundcubemail-1.6.4-complete.tar.gz
mkdir -p /var/www/roundcube
cp -r roundcubemail-1.6.4/* /var/www/roundcube/
chown -R www-data:www-data /var/www/roundcube/

# Configure Roundcube
echo "Configuring Roundcube..."
cp /var/www/roundcube/config/config.inc.php.sample /var/www/roundcube/config/config.inc.php
DES_KEY=$(openssl rand -base64 24)

sed -i "s/\$config\['db_dsnw'\] = .*/\$config\['db_dsnw'\] = 'mysql:\/\/roundcube:$DB_PASSWORD@localhost\/roundcube';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['default_host'\] = .*/\$config\['default_host'\] = 'localhost';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['smtp_server'\] = .*/\$config\['smtp_server'\] = 'localhost';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['smtp_port'\] = .*/\$config\['smtp_port'\] = 25;/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['product_name'\] = .*/\$config\['product_name'\] = 'Glory Education Center Webmail';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['des_key'\] = .*/\$config\['des_key'\] = '$DES_KEY';/g" /var/www/roundcube/config/config.inc.php

# Initialize Roundcube database
echo "Initializing Roundcube database..."
mysql roundcube < /var/www/roundcube/SQL/mysql.initial.sql

# Remove installer and secure config
echo "Securing Roundcube installation..."
rm -rf /var/www/roundcube/installer
chmod 640 /var/www/roundcube/config/config.inc.php
chown www-data:www-data /var/www/roundcube/config/config.inc.php

# STEP 7: OpenDKIM Configuration
echo "\n[STEP 7] Configuring OpenDKIM"

# Create OpenDKIM configuration file
echo "Creating OpenDKIM configuration..."
cat > /etc/opendkim.conf << EOF
# OpenDKIM configuration
SyslogSuccess             yes
LogWhy                    yes

# Common options
Domain                  $DOMAIN
KeyFile                 /etc/opendkim/keys/$DOMAIN/mail.private
Selector                mail
Canonization            relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256
UserID                  opendkim:opendkim
Socket                  inet:12301@localhost

# Always oversign From (sign using actual From and a null From)
OversignHeaders         From
EOF

# Create directory structure for OpenDKIM
echo "Setting up OpenDKIM directories..."
mkdir -p /etc/opendkim/keys/$DOMAIN
mkdir -p /var/run/opendkim
chown opendkim:opendkim /var/run/opendkim

# Create trusted hosts file
echo "Creating trusted hosts file..."
cat > /etc/opendkim/TrustedHosts << EOF
127.0.0.1
localhost
$DOMAIN
$MAIL_HOSTNAME
EOF

# Generate DKIM keys
echo "Generating DKIM keys..."
cd /etc/opendkim/keys/$DOMAIN
opendkim-genkey -b 2048 -d $DOMAIN -s mail -v
chown opendkim:opendkim mail.private
chmod 600 mail.private

# Setup KeyTable and SigningTable
echo "Setting up KeyTable and SigningTable..."
echo "mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/$DOMAIN/mail.private" > /etc/opendkim/KeyTable
echo "*@$DOMAIN mail._domainkey.$DOMAIN" > /etc/opendkim/SigningTable

# Set proper permissions
echo "Setting proper permissions for OpenDKIM..."
chown -R opendkim:opendkim /etc/opendkim
chmod -R go-rwx /etc/opendkim/keys

# Add OpenDKIM to Postfix
echo "Configuring Postfix to use OpenDKIM..."
cat >> /etc/postfix/main.cf << EOF

# OpenDKIM
milter_protocol = 2
milter_default_action = accept
smtpd_milters = inet:localhost:12301
non_smtpd_milters = inet:localhost:12301
EOF

# STEP 8: Fail2ban configuration
echo "\n[STEP 8] Configuring Fail2ban"

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 86400
findtime = 3600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled = true

[postfix]
enabled = true
filter = postfix
port = smtp,submission,smtps
logpath = /var/log/mail.log

[dovecot]
enabled = true
filter = dovecot
logpath = /var/log/mail.log

[roundcube-auth]
enabled = true
filter = roundcube-auth
port = http,https
logpath = /var/log/apache2/roundcube_error.log
maxretry = 3
EOF

cat > /etc/fail2ban/filter.d/roundcube-auth.conf << EOF
[Definition]
failregex = FAILED login for .* from <HOST>
ignoreregex =
EOF

# Create login test file
echo "\n[STEP 9] Creating diagnostic tools"

# Create login test script
cat > /var/www/roundcube/check-login.php << EOF
<?php
// Script to test Roundcube login directly
define('INSTALL_PATH', realpath(dirname(__FILE__)) . '/');
require_once INSTALL_PATH . 'program/include/iniset.php';

// Enable error reporting
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Check if form was submitted
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = isset($_POST['username']) ? $_POST['username'] : '';
    $password = isset($_POST['password']) ? $_POST['password'] : '';
    
    if (empty($username) || empty($password)) {
        $error = "Please enter both username and password";
    } else {
        // Initialize Roundcube app
        $rcmail = rcmail::get_instance();
        
        // Try to connect to IMAP directly
        $imap_host = $rcmail->config->get('default_host', 'localhost');
        $imap_port = 143;
        $use_ssl = false;
        
        echo "<div style='background:#333; color:#fff; padding:10px; margin:10px 0; font-family:monospace;'>";
        echo "Attempting direct IMAP connection to: $imap_host:$imap_port<br>";
        
        // Try direct socket connection
        $socket = @fsockopen(($use_ssl ? 'ssl://' : '') . $imap_host, $imap_port, $errno, $errstr, 5);
        if (!$socket) {
            echo "SOCKET ERROR: ($errno) $errstr<br>";
        } else {
            echo "Socket connection: SUCCESS<br>";
            
            // Read greeting
            $greeting = fgets($socket, 1024);
            echo "IMAP greeting: " . htmlspecialchars($greeting) . "<br>";
            
            // Try login
            $login_cmd = "A1 LOGIN \"$username\" \"$password\"\r\n";
            echo "Sending: A1 LOGIN \"$username\" ********<br>";
            fwrite($socket, $login_cmd);
            $response = fgets($socket, 1024);
            echo "Response: " . htmlspecialchars($response) . "<br>";
            
            // Logout
            fwrite($socket, "A2 LOGOUT\r\n");
            fclose($socket);
        }
        echo "</div>";
        
        // Try Roundcube's authentication
        echo "<div style='background:#333; color:#fff; padding:10px; margin:10px 0; font-family:monospace;'>";
        echo "Attempting full Roundcube login<br>";
        
        try {
            // Initialize login
            $auth = $rcmail->plugins->exec_hook('authenticate', array(
                'host' => $imap_host,
                'user' => $username,
                'pass' => $password,
                'cookiecheck' => true,
                'valid' => true
            ));
            
            if ($auth['valid'] && !$auth['abort']) {
                $login = $rcmail->login($auth['user'], $auth['pass'], $auth['host'], $auth['cookiecheck']);
                
                if ($login) {
                    echo "Full Roundcube login: SUCCESS<br>";
                    $rcmail->logout_actions();
                    $rcmail->kill_session();
                } else {
                    echo "Full Roundcube login: FAILED<br>";
                    echo "Error: " . $rcmail->get_error() . "<br>";
                }
            } else {
                echo "Authentication hook failed<br>";
                echo "Error: " . ($auth['error'] ?? 'Unknown error') . "<br>";
            }
        } catch (Exception $e) {
            echo "EXCEPTION: " . $e->getMessage() . "<br>";
        }
        echo "</div>";
    }
}
?>

<!DOCTYPE html>
<html>
<head>
    <title>Roundcube Login Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f5f5f5;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #0078d7;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="text"],
        input[type="password"] {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }
        button {
            background-color: #0078d7;
            color: white;
            border: none;
            padding: 10px 15px;
            border-radius: 4px;
            cursor: pointer;
        }
        .error {
            color: red;
            margin-bottom: 15px;
        }
        .info {
            background-color: #f0f0f0;
            padding: 10px;
            border-radius: 4px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Roundcube Login Test</h1>
        
        <div class="info">
            This tool tests Roundcube login to help diagnose issues.
        </div>
        
        <?php if (isset($error)): ?>
            <div class="error"><?php echo $error; ?></div>
        <?php endif; ?>
        
        <form method="post">
            <div class="form-group">
                <label for="username">Email Address:</label>
                <input type="text" id="username" name="username" value="<?php echo isset($_POST['username']) ? htmlspecialchars($_POST['username']) : ''; ?>">
            </div>
            
            <div class="form-group">
                <label for="password">Password:</label>
                <input type="password" id="password" name="password">
            </div>
            
            <button type="submit">Test Login</button>
        </form>
        
        <div class="info" style="margin-top: 20px;">
            <h3>Server Information:</h3>
            <p>PHP Version: <?php echo phpversion(); ?></p>
            <p>Roundcube Version: <?php echo RCMAIL_VERSION; ?></p>
            <p>Default IMAP Host: <?php echo rcmail::get_instance()->config->get('default_host', 'Not configured'); ?></p>
            <p>Default SMTP Server: <?php echo rcmail::get_instance()->config->get('smtp_server', 'Not configured'); ?></p>
        </div>
    </div>
</body>
</html>
EOF

chown www-data:www-data /var/www/roundcube/check-login.php

# Create mail user management script
cat > /usr/local/bin/add_mail_user.sh << EOF
#!/bin/bash
# Script to create a new email account

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Check for correct number of arguments
if [ $# -ne 2 ]; then
  echo "Usage: $0 <email> <password>"
  exit 1
fi

EMAIL=$1
PASSWORD=$2
DOMAIN=$(echo $EMAIL | cut -d@ -f2)
USER=$(echo $EMAIL | cut -d@ -f1)

# Validate domain
if [ "$DOMAIN" != "gloryeducationcenter.in" ]; then
  echo "Error: Email must be in the domain gloryeducationcenter.in"
  exit 1
fi

# Create password hash
HASH=$(doveadm pw -s SHA512-CRYPT -p "$PASSWORD")

# Add to password file
echo "$EMAIL:$HASH" >> /etc/dovecot/users

# Add to Postfix virtual mailbox file
echo "$EMAIL $DOMAIN/$USER/" >> /etc/postfix/vmailbox
postmap /etc/postfix/vmailbox

# Create mailbox directory
MAILDIR="/var/mail/vhosts/$DOMAIN/$USER"
mkdir -p $MAILDIR/{cur,new,tmp}
chown -R vmail:vmail $MAILDIR

echo "User $EMAIL created successfully."
echo "They can now log in at https://mail.$DOMAIN"
EOF

chmod +x /usr/local/bin/add_mail_user.sh

# STEP 10: Start services
echo "\n[STEP 10] Starting all services"

# Make sure the services are enabled at boot
systemctl enable postfix dovecot apache2 opendkim mariadb fail2ban

# Start services
echo "Starting database service..."
systemctl start mariadb

echo "Starting mail services..."
systemctl start dovecot
systemctl start postfix

echo "Starting OpenDKIM..."
systemctl start opendkim

echo "Starting web server..."
systemctl start apache2

echo "Starting Fail2ban..."
systemctl start fail2ban

# STEP 11: Generate DNS configuration
echo "\n[STEP 11] Generating DNS configuration instructions"

DKIM_RECORD=$(cat /etc/opendkim/keys/$DOMAIN/mail.txt | grep -o 'p=.*"' | tr -d '"' | tr -d ' ')

echo "\n========================================================="
echo "               INSTALLATION COMPLETE                  "
echo "========================================================="
echo "\nDNS RECORDS TO ADD IN CLOUDFLARE:\n"

echo "MX record:"
echo "Type: MX"
echo "Name: @ (root domain)"
echo "Priority: 10"
echo "Value: $MAIL_HOSTNAME."
echo "TTL: Auto"
echo "Proxy status: DNS only (grey cloud - important!)"

echo "\nA record for mail server:"
echo "Type: A"
echo "Name: mail"
echo "Value: $SERVER_IP"
echo "TTL: Auto"
echo "Proxy status: DNS only (grey cloud)"

echo "\nSPF record:"
echo "Type: TXT"
echo "Name: @ (root domain)"
echo "Value: v=spf1 mx ip4:$SERVER_IP ~all"
echo "TTL: Auto"
echo "Proxy status: DNS only (grey cloud)"

echo "\nDKIM record:"
echo "Type: TXT"
echo "Name: mail._domainkey"
echo "Value: $DKIM_RECORD"
echo "TTL: Auto"
echo "Proxy status: DNS only (grey cloud)"

echo "\nDMARC record:"
echo "Type: TXT"
echo "Name: _dmarc"
echo "Value: v=DMARC1; p=quarantine; rua=mailto:$ADMIN_EMAIL"
echo "TTL: Auto"
echo "Proxy status: DNS only (grey cloud)"

echo "\nIMPORTANT NOTES:"
echo "1. All email-related DNS records MUST use DNS only mode (grey cloud)."
echo "2. Wait for DNS propagation before sending/receiving emails (can take up to 24-48 hours)."
echo "3. Your webmail is accessible at: https://$MAIL_HOSTNAME"
echo "4. Login with: $ADMIN_EMAIL and your chosen password"
echo "5. To create additional email accounts, use: sudo /usr/local/bin/add_mail_user.sh email@$DOMAIN password"
echo "6. If you encounter login issues, visit: https://$MAIL_HOSTNAME/check-login.php"
echo "7. Database password for Roundcube (save for reference): $DB_PASSWORD"
echo "\n========================================================="
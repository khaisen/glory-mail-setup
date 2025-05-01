#!/bin/bash
# Mail Server Installation Script for gloryeducationcenter.in with Cloudflare integration
# This script must be run as root on an Ubuntu/Debian system

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Variables
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"  # Using mail subdomain for both MX and webmail
ADMIN_EMAIL="admin@$DOMAIN"
ADMIN_PASSWORD="" # Will prompt for this
DB_PASSWORD=$(openssl rand -base64 12)
CERTS_DIR="/etc/cloudflare/certs"
LOCAL_CERT_PATH="./certificates"  # Path to your local certificates folder

# Prompt for admin password
read -s -p "Enter password for $ADMIN_EMAIL: " ADMIN_PASSWORD
echo ""
if [ -z "$ADMIN_PASSWORD" ]; then
  echo "Password cannot be empty"
  exit 1
fi

# Check for certificate files
if [ ! -d "$LOCAL_CERT_PATH" ]; then
  echo "Error: Certificate directory '$LOCAL_CERT_PATH' not found"
  exit 1
fi

if [ ! -f "$LOCAL_CERT_PATH/origin-certificate.pem" ] || [ ! -f "$LOCAL_CERT_PATH/private-key.pem" ]; then
  echo "Error: Certificate files not found in '$LOCAL_CERT_PATH'"
  echo "Expected files: origin-certificate.pem and private-key.pem"
  exit 1
fi

# Update system
echo "Updating system..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y curl wget gnupg2 ca-certificates lsb-release apt-transport-https
apt install -y postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql
apt install -y apache2 php php-common php-imap php-json php-curl php-zip php-xml php-mbstring php-imagick php-mysql php-intl mariadb-server
apt install -y fail2ban opendkim opendkim-tools postfix-policyd-spf-python

# Set hostname for mail server functions
echo "Setting hostname..."
hostnamectl set-hostname $MAIL_HOSTNAME

# Update hosts file
if ! grep -q "$MAIL_HOSTNAME" /etc/hosts; then
  echo "127.0.1.1 $MAIL_HOSTNAME mail" >> /etc/hosts
fi

# Configure firewall
echo "Configuring firewall..."
apt install -y ufw
ufw allow ssh
ufw allow 25/tcp
ufw allow 465/tcp
ufw allow 587/tcp
ufw allow 110/tcp
ufw allow 995/tcp
ufw allow 143/tcp
ufw allow 993/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Create mail directories and user
echo "Setting up mail directories..."
mkdir -p /var/mail/vhosts/$DOMAIN
groupadd -g 5000 vmail 2>/dev/null || true
useradd -g vmail -u 5000 -d /var/mail/vhosts -s /usr/sbin/nologin vmail 2>/dev/null || true
chown -R vmail:vmail /var/mail/vhosts

# Create directory for Cloudflare certificates and copy them
echo "Setting up Cloudflare certificates..."
mkdir -p $CERTS_DIR
cp "$LOCAL_CERT_PATH/origin-certificate.pem" "$CERTS_DIR/"
cp "$LOCAL_CERT_PATH/private-key.pem" "$CERTS_DIR/"

# Set proper permissions
chmod 600 $CERTS_DIR/private-key.pem
chmod 644 $CERTS_DIR/origin-certificate.pem

# Configure Postfix
echo "Configuring Postfix..."
cp /etc/postfix/main.cf /etc/postfix/main.cf.bak

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

# Configure vmailbox and virtual
echo "$ADMIN_EMAIL $DOMAIN/admin/" > /etc/postfix/vmailbox
echo "@$DOMAIN $ADMIN_EMAIL" > /etc/postfix/virtual
postmap /etc/postfix/vmailbox
postmap /etc/postfix/virtual

# Configure master.cf
sed -i 's/#submission/submission/g' /etc/postfix/master.cf
sed -i 's/#smtps/smtps/g' /etc/postfix/master.cf

# Configure Dovecot
echo "Configuring Dovecot..."
sed -i 's/^#protocols = imap pop3 lmtp/protocols = imap pop3 lmtp/g' /etc/dovecot/dovecot.conf

# Configure mail location
sed -i 's/^mail_location = .*/mail_location = maildir:\/var\/mail\/vhosts\/%d\/%n/g' /etc/dovecot/conf.d/10-mail.conf
echo "mail_privileged_group = vmail" >> /etc/dovecot/conf.d/10-mail.conf

# Configure authentication
sed -i 's/^auth_mechanisms = .*/auth_mechanisms = plain login/g' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#!include auth-system.conf.ext/!include auth-system.conf.ext\n#!include auth-sql.conf.ext\n#!include auth-ldap.conf.ext\n#!include auth-passwdfile.conf.ext\n!include auth-static.conf.ext/g' /etc/dovecot/conf.d/10-auth.conf

# Create static auth config
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

# Configure SSL
cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = required
ssl_cert = <$CERTS_DIR/origin-certificate.pem
ssl_key = <$CERTS_DIR/private-key.pem
ssl_min_protocol = TLSv1.2
ssl_prefer_server_ciphers = yes
EOF

# Configure Dovecot master
sed -i '/unix_listener auth-userdb {/,/}/c\  unix_listener auth-userdb {\n    mode = 0600\n    user = vmail\n  }' /etc/dovecot/conf.d/10-master.conf
sed -i '/# Postfix smtp-auth/,/}/c\  # Postfix smtp-auth\n  unix_listener \/var\/spool\/postfix\/private\/auth {\n    mode = 0666\n    user = postfix\n    group = postfix\n  }' /etc/dovecot/conf.d/10-master.conf

# Configure Apache for webmail
echo "Configuring Apache..."
a2dissite 000-default.conf

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

a2ensite $MAIL_HOSTNAME.conf
a2enmod rewrite ssl

# Configure database for Roundcube
echo "Setting up MySQL for Roundcube..."
mysql -e "CREATE DATABASE roundcube DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;" || true
mysql -e "GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost' IDENTIFIED BY '$DB_PASSWORD';" || true
mysql -e "FLUSH PRIVILEGES;"

# Install Roundcube
echo "Installing Roundcube..."
cd /tmp
wget https://github.com/roundcube/roundcubemail/releases/download/1.6.4/roundcubemail-1.6.4-complete.tar.gz
tar -xvf roundcubemail-1.6.4-complete.tar.gz
mkdir -p /var/www/roundcube
cp -r roundcubemail-1.6.4/* /var/www/roundcube/
chown -R www-data:www-data /var/www/roundcube/

# Configure Roundcube
cp /var/www/roundcube/config/config.inc.php.sample /var/www/roundcube/config/config.inc.php
DES_KEY=$(openssl rand -base64 24)

sed -i "s/\$config\['db_dsnw'\] = .*/\$config\['db_dsnw'\] = 'mysql:\/\/roundcube:$DB_PASSWORD@localhost\/roundcube';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['default_host'\] = .*/\$config\['default_host'\] = 'localhost';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['smtp_server'\] = .*/\$config\['smtp_server'\] = 'localhost';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['smtp_port'\] = .*/\$config\['smtp_port'\] = 25;/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['product_name'\] = .*/\$config\['product_name'\] = 'Glory Education Center Webmail';/g" /var/www/roundcube/config/config.inc.php
sed -i "s/\$config\['des_key'\] = .*/\$config\['des_key'\] = '$DES_KEY';/g" /var/www/roundcube/config/config.inc.php

# Initialize Roundcube database
mysql roundcube < /var/www/roundcube/SQL/mysql.initial.sql || true

# Secure Roundcube
rm -rf /var/www/roundcube/installer
chmod 640 /var/www/roundcube/config/config.inc.php
chown www-data:www-data /var/www/roundcube/config/config.inc.php

# Configure OpenDKIM
echo "Configuring OpenDKIM..."
cat > /etc/opendkim.conf << EOF
Domain                  $DOMAIN
KeyFile                 /etc/opendkim/keys/$DOMAIN/mail.private
Selector                mail
Socket                  inet:12301@localhost
TrustAnchorFile         /usr/share/dns/root.key
UserID                  opendkim
EOF

mkdir -p /etc/opendkim/keys/$DOMAIN
chown -R opendkim:opendkim /etc/opendkim
opendkim-genkey -b 2048 -d $DOMAIN -D /etc/opendkim/keys/$DOMAIN -s mail
chown opendkim:opendkim /etc/opendkim/keys/$DOMAIN/mail.private

echo "mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/$DOMAIN/mail.private" > /etc/opendkim/KeyTable
echo "*@$DOMAIN mail._domainkey.$DOMAIN" > /etc/opendkim/SigningTable
echo -e "127.0.0.1\nlocalhost" > /etc/opendkim/TrustedHosts

# Add OpenDKIM to Postfix
echo -e "\n# OpenDKIM\nmilter_protocol = 2\nmilter_default_action = accept\nsmtpd_milters = inet:localhost:12301\nnon_smtpd_milters = inet:localhost:12301" >> /etc/postfix/main.cf

# Configure Fail2ban
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

# Create admin user
mkdir -p /var/mail/vhosts/$DOMAIN/admin/{cur,new,tmp}
chown -R vmail:vmail /var/mail/vhosts/$DOMAIN

# Generate password hash
DOVECOT_PASS=$(doveadm pw -s SHA512-CRYPT -p "$ADMIN_PASSWORD")
echo "$ADMIN_EMAIL:$DOVECOT_PASS" > /etc/dovecot/users
chmod 600 /etc/dovecot/users
chown vmail:dovecot /etc/dovecot/users

# Restart all services
systemctl restart postfix
systemctl restart dovecot
systemctl restart opendkim
systemctl restart apache2
systemctl restart fail2ban

# Enable services on boot
systemctl enable postfix dovecot opendkim apache2 fail2ban

# Output DNS configuration info
echo ""
echo "==========================================================="
echo "Mail server installation complete!"
echo "==========================================================="
echo ""
echo "IMPORTANT: Add the following DNS records to your Cloudflare dashboard:"
echo ""
echo "MX record:"
echo "Type: MX"
echo "Name: @ (or leave blank for root domain)"
echo "Mail server: $MAIL_HOSTNAME."
echo "Priority: 10"
echo "Proxy status: DNS only (grey cloud)"
echo ""
echo "A record:"
echo "Type: A"
echo "Name: mail"
echo "IPv4 address: YOUR_SERVER_IP"
echo "Proxy status: DNS only (grey cloud)"
echo ""
echo "SPF record:"
echo "Type: TXT"
echo "Name: @ (or leave blank for root domain)"
echo "Content: v=spf1 mx ip4:YOUR_SERVER_IP ~all"
echo "Proxy status: DNS only (grey cloud)"
echo ""
echo "DKIM record:"
echo "Type: TXT"
echo "Name: mail._domainkey"
echo "Content: $(cat /etc/opendkim/keys/$DOMAIN/mail.txt | grep -o 'p=.*"' | tr -d '"' | tr -d ' ')"
echo "Proxy status: DNS only (grey cloud)"
echo ""
echo "DMARC record:"
echo "Type: TXT"
echo "Name: _dmarc"
echo "Content: v=DMARC1; p=quarantine; rua=mailto:$ADMIN_EMAIL"
echo "Proxy status: DNS only (grey cloud)"
echo ""
echo "REMEMBER: All email-related DNS records MUST use DNS only mode (grey cloud), not proxied mode."
echo ""
echo "Access your webmail at: https://$MAIL_HOSTNAME"
echo "Login: $ADMIN_EMAIL"
echo "Password: (the one you entered)"
echo ""
echo "Database password for Roundcube (save for reference): $DB_PASSWORD"
echo ""
echo "==========================================================="
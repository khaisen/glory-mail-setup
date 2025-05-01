#!/bin/bash
# Script to properly restart all mail services
# Run as root

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "            RESTARTING ALL MAIL SERVICES               "
echo "========================================================="

# First, stop all services in the correct order
echo "Stopping services in proper order..."
systemctl stop apache2
systemctl stop postfix
systemctl stop dovecot
systemctl stop opendkim
systemctl stop mariadb

echo "Waiting for services to fully stop..."
sleep 5

# Fix certificate permissions
echo "Fixing certificate permissions..."
if [ -d "/etc/cloudflare/certs" ]; then
  chown root:root /etc/cloudflare/certs/origin-certificate.pem
  chmod 644 /etc/cloudflare/certs/origin-certificate.pem
  chown root:root /etc/cloudflare/certs/private-key.pem
  chmod 640 /etc/cloudflare/certs/private-key.pem
  echo "Certificate permissions updated."
fi

# Fix mailbox permissions
echo "Fixing mailbox permissions..."
DOMAIN="gloryeducationcenter.in"
if [ -d "/var/mail/vhosts/$DOMAIN" ]; then
  chown -R vmail:vmail /var/mail/vhosts/$DOMAIN
  find /var/mail/vhosts/$DOMAIN -type d -exec chmod 700 {} \;
  find /var/mail/vhosts/$DOMAIN -type f -exec chmod 600 {} \;
  echo "Mailbox permissions updated."
fi

# Start database first
echo "Starting MariaDB..."
systemctl start mariadb
sleep 2
systemctl status mariadb --no-pager

# Start each service one by one
echo "Starting Dovecot..."
systemctl start dovecot
sleep 2
systemctl status dovecot --no-pager

echo "Starting Postfix..."
systemctl start postfix
sleep 2
systemctl status postfix --no-pager

echo "Starting OpenDKIM..."
systemctl start opendkim
sleep 2
systemctl status opendkim --no-pager

echo "Starting Apache..."
systemctl start apache2
sleep 2
systemctl status apache2 --no-pager

# Verify Roundcube configuration
echo "\nVerifying Roundcube configuration..."
ROUNDCUBE_CONFIG="/var/www/roundcube/config/config.inc.php"
if [ -f "$ROUNDCUBE_CONFIG" ]; then
  # Check if default_host is properly set
  if ! grep -q "\$config\['default_host'\] = 'localhost';" "$ROUNDCUBE_CONFIG"; then
    echo "Fixing Roundcube IMAP host configuration..."
    sed -i "s/\$config\['default_host'\] = .*/\$config\['default_host'\] = 'localhost';/g" "$ROUNDCUBE_CONFIG"
  fi
  
  # Check if smtp_server is properly set
  if ! grep -q "\$config\['smtp_server'\] = 'localhost';" "$ROUNDCUBE_CONFIG"; then
    echo "Fixing Roundcube SMTP server configuration..."
    sed -i "s/\$config\['smtp_server'\] = .*/\$config\['smtp_server'\] = 'localhost';/g" "$ROUNDCUBE_CONFIG"
  fi
  
  # Set proper permissions
  chown www-data:www-data "$ROUNDCUBE_CONFIG"
  chmod 640 "$ROUNDCUBE_CONFIG"
  
  echo "Roundcube configuration verified."
fi

# Test IMAP connection
echo "\nTesting IMAP connection..."
apt-get install -y netcat telnet 2>/dev/null
echo "Trying to connect to IMAP port..."
if nc -z -v localhost 143 2>/dev/null; then
  echo "IMAP connection successful!"
else
  echo "IMAP connection failed!"
fi

echo "\nAll services have been restarted. Please try logging in again at https://mail.$DOMAIN"
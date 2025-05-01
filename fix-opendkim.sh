#!/bin/bash
# OpenDKIM Fix Script
# Run as root

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "              OPENDKIM REPAIR SCRIPT                    "
echo "========================================================="

# Stop the service first
systemctl stop opendkim

# Check for common issues
DOMAIN="gloryeducationcenter.in"
KEYS_DIR="/etc/opendkim/keys/$DOMAIN"
CONF_FILE="/etc/opendkim.conf"

# 1. Fix configuration file
echo "Checking OpenDKIM configuration..."
if [ -f "$CONF_FILE" ]; then
  echo "Found configuration file"
  
  # Create a backup
  cp "$CONF_FILE" "$CONF_FILE.bak"
  
  # Create a new configuration file with verified settings
  cat > "$CONF_FILE" << EOF
# OpenDKIM configuration
SyslogSuccess             yes
LogWhy                    yes

# Common options
Canonization              relaxed/simple
ExternalIgnoreList        refile:/etc/opendkim/TrustedHosts
InternalHosts             refile:/etc/opendkim/TrustedHosts
KeyTable                  refile:/etc/opendkim/KeyTable
SigningTable              refile:/etc/opendkim/SigningTable
Mode                      sv
PidFile                   /var/run/opendkim/opendkim.pid
SignatureAlgorithm        rsa-sha256
UserID                    opendkim:opendkim
Socket                    inet:12301@localhost

# Always oversign From (sign using actual From and a null From)
OversignHeaders           From

# List domains to use for RFC 6541 DKIM Authorized Third-Party Signatures
#ATPSDomains              example.com
EOF
  echo "Created new configuration file"
else
  echo "ERROR: Configuration file not found!"
  exit 1
fi

# 2. Ensure directory structure exists
echo "Checking OpenDKIM directories..."
mkdir -p "$KEYS_DIR"
chown -R opendkim:opendkim /etc/opendkim

# 3. Fix table files
echo "Creating OpenDKIM table files..."

# TrustedHosts file
cat > /etc/opendkim/TrustedHosts << EOF
127.0.0.1
localhost
$DOMAIN
mail.$DOMAIN
EOF

# 4. Regenerate keys (backup old ones first)
echo "Regenerating DKIM keys..."
if [ -f "$KEYS_DIR/mail.private" ]; then
  mv "$KEYS_DIR/mail.private" "$KEYS_DIR/mail.private.bak"
fi
if [ -f "$KEYS_DIR/mail.txt" ]; then
  mv "$KEYS_DIR/mail.txt" "$KEYS_DIR/mail.txt.bak"
fi

# Generate new keys
cd /etc/opendkim/keys/$DOMAIN
opendkim-genkey -b 2048 -d $DOMAIN -s mail -v
chown opendkim:opendkim mail.private
chmod 600 mail.private

# 5. Update KeyTable and SigningTable
echo "Updating KeyTable and SigningTable..."
echo "mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/$DOMAIN/mail.private" > /etc/opendkim/KeyTable
echo "*@$DOMAIN mail._domainkey.$DOMAIN" > /etc/opendkim/SigningTable

# 6. Fix permissions
echo "Fixing permissions..."
chown -R opendkim:opendkim /etc/opendkim
chmod -R go-rwx /etc/opendkim/keys

# 7. Fix socket directory
echo "Fixing socket directory..."
mkdir -p /var/run/opendkim
chown opendkim:opendkim /var/run/opendkim

# 8. Update DNS record information
echo "\nNew DKIM DNS record (add this to your DNS as a TXT record):\n"
echo "Name: mail._domainkey"
echo "Content: $(cat $KEYS_DIR/mail.txt | grep -o 'p=.*"' | tr -d '"' | tr -d ' ')"

# 9. Test configuration
echo "\nTesting OpenDKIM configuration..."
opendkim-testkey -d $DOMAIN -s mail -k $KEYS_DIR/mail.private -v

# 10. Restart OpenDKIM
echo "\nRestarting OpenDKIM service..."
systemctl start opendkim
sleep 5
systemctl status opendkim

# 11. Restart Postfix to use the new OpenDKIM configuration
echo "\nRestarting Postfix..."
systemctl restart postfix

echo "\nOpenDKIM repair completed. Check the status above to see if it started successfully."
echo "If it's still not working, check the logs with: journalctl -xeu opendkim.service"
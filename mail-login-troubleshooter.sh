#!/bin/bash
# Comprehensive Mail Server Login Troubleshooting Script
# Run as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

echo "========================================================="
echo "       MAIL SERVER LOGIN TROUBLESHOOTING SCRIPT        "
echo "========================================================="

# Variables
DOMAIN="gloryeducationcenter.in"
MAIL_HOSTNAME="mail.$DOMAIN"
ADMIN_EMAIL="admin@$DOMAIN"
ROUNDCUBE_PATH="/var/www/roundcube"
DATE_SUFFIX=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/mail_troubleshoot_$DATE_SUFFIX.log"

echo "Starting diagnostics at $(date)" | tee -a "$LOG_FILE"
echo "Results will be saved to $LOG_FILE"

# Function to check if a service is running
check_service() {
  local service=$1
  echo "\n[Checking $service status]" | tee -a "$LOG_FILE"
  
  systemctl status $service | head -n 10 | tee -a "$LOG_FILE"
  
  if systemctl is-active --quiet $service; then
    echo "$service is RUNNING" | tee -a "$LOG_FILE"
    return 0
  else
    echo "$service is NOT RUNNING" | tee -a "$LOG_FILE"
    return 1
  fi
}

# Check service statuses
echo "\n--- Checking Service Statuses ---" | tee -a "$LOG_FILE"
check_service postfix
check_service dovecot
check_service apache2
check_service mysql
check_service opendkim

# Check mail logs for errors
echo "\n--- Checking Mail Logs for Errors ---" | tee -a "$LOG_FILE"
echo "Last 50 lines from mail.log:" | tee -a "$LOG_FILE"
grep -i "error\|failed\|warning\|fatal" /var/log/mail.log | tail -n 50 | tee -a "$LOG_FILE"

# Check Apache logs for errors
echo "\n--- Checking Apache Logs for Errors ---" | tee -a "$LOG_FILE"
echo "Last 50 lines from Apache error log:" | tee -a "$LOG_FILE"
tail -n 50 /var/log/apache2/error.log | tee -a "$LOG_FILE"
echo "\nLast 50 lines from Roundcube error log:" | tee -a "$LOG_FILE"
tail -n 50 /var/log/apache2/roundcube_error.log 2>/dev/null | tee -a "$LOG_FILE"

# Check Roundcube configuration
echo "\n--- Checking Roundcube Configuration ---" | tee -a "$LOG_FILE"
if [ -f "$ROUNDCUBE_PATH/config/config.inc.php" ]; then
  echo "Roundcube config exists" | tee -a "$LOG_FILE"
  echo "Database connection string:" | tee -a "$LOG_FILE"
  grep -A 2 db_dsnw "$ROUNDCUBE_PATH/config/config.inc.php" | tee -a "$LOG_FILE"
  echo "IMAP settings:" | tee -a "$LOG_FILE"
  grep -A 2 default_host "$ROUNDCUBE_PATH/config/config.inc.php" | tee -a "$LOG_FILE"
  echo "SMTP settings:" | tee -a "$LOG_FILE"
  grep -A 2 smtp_server "$ROUNDCUBE_PATH/config/config.inc.php" | tee -a "$LOG_FILE"
else
  echo "ERROR: Roundcube config file not found!" | tee -a "$LOG_FILE"
fi

# Check MySQL database
echo "\n--- Checking MySQL Roundcube Database ---" | tee -a "$LOG_FILE"
if mysql -e "SHOW DATABASES;" | grep -q roundcube; then
  echo "Roundcube database exists" | tee -a "$LOG_FILE"
  echo "Tables in the database:" | tee -a "$LOG_FILE"
  mysql -e "SHOW TABLES FROM roundcube;" | tee -a "$LOG_FILE"
else
  echo "ERROR: Roundcube database does not exist!" | tee -a "$LOG_FILE"
fi

# Check Dovecot configuration and users
echo "\n--- Checking Dovecot Configuration ---" | tee -a "$LOG_FILE"
if [ -f "/etc/dovecot/dovecot.conf" ]; then
  echo "Dovecot config exists" | tee -a "$LOG_FILE"
  echo "Checking auth mechanisms:" | tee -a "$LOG_FILE"
  grep auth_mechanisms /etc/dovecot/conf.d/10-auth.conf | tee -a "$LOG_FILE"
  echo "Checking SSL configuration:" | tee -a "$LOG_FILE"
  grep -A 5 "^ssl =" /etc/dovecot/conf.d/10-ssl.conf | tee -a "$LOG_FILE"
  echo "Checking mail location:" | tee -a "$LOG_FILE"
  grep mail_location /etc/dovecot/conf.d/10-mail.conf | tee -a "$LOG_FILE"
else
  echo "ERROR: Dovecot config file not found!" | tee -a "$LOG_FILE"
fi

# Check user file
echo "\n--- Checking Dovecot Users ---" | tee -a "$LOG_FILE"
if [ -f "/etc/dovecot/users" ]; then
  echo "Users file exists" | tee -a "$LOG_FILE"
  echo "Number of users: $(wc -l < /etc/dovecot/users)" | tee -a "$LOG_FILE"
  echo "Checking for admin user:" | tee -a "$LOG_FILE"
  if grep -q "^$ADMIN_EMAIL:" /etc/dovecot/users; then
    echo "Admin user found in users file" | tee -a "$LOG_FILE"
  else
    echo "ERROR: Admin user NOT found in users file!" | tee -a "$LOG_FILE"
  fi
  echo "Checking file permissions:" | tee -a "$LOG_FILE"
  ls -la /etc/dovecot/users | tee -a "$LOG_FILE"
else
  echo "ERROR: Dovecot users file not found!" | tee -a "$LOG_FILE"
fi

# Check mailbox directory
echo "\n--- Checking Mailbox Directory ---" | tee -a "$LOG_FILE"
MAILDIR="/var/mail/vhosts/$DOMAIN/admin"
if [ -d "$MAILDIR" ]; then
  echo "Mailbox directory exists" | tee -a "$LOG_FILE"
  echo "Directory structure:" | tee -a "$LOG_FILE"
  ls -la "$MAILDIR" | tee -a "$LOG_FILE"
  echo "Permissions and ownership:" | tee -a "$LOG_FILE"
  find "$MAILDIR" -type d -exec ls -ld {} \; | tee -a "$LOG_FILE"
else
  echo "ERROR: Mailbox directory not found!" | tee -a "$LOG_FILE"
fi

# Check certificates
echo "\n--- Checking SSL Certificates ---" | tee -a "$LOG_FILE"
CERTS_DIR="/etc/cloudflare/certs"
if [ -d "$CERTS_DIR" ]; then
  echo "Certificates directory exists" | tee -a "$LOG_FILE"
  echo "Files:" | tee -a "$LOG_FILE"
  ls -la "$CERTS_DIR" | tee -a "$LOG_FILE"
  
  if [ -f "$CERTS_DIR/origin-certificate.pem" ]; then
    echo "Certificate info:" | tee -a "$LOG_FILE"
    openssl x509 -in "$CERTS_DIR/origin-certificate.pem" -noout -subject -issuer -dates | tee -a "$LOG_FILE"
  else
    echo "ERROR: Certificate file not found!" | tee -a "$LOG_FILE"
  fi
else
  echo "ERROR: Certificates directory not found!" | tee -a "$LOG_FILE"
fi

# Check Postfix virtual mappings
echo "\n--- Checking Postfix Configuration ---" | tee -a "$LOG_FILE"
if [ -f "/etc/postfix/vmailbox" ]; then
  echo "Virtual mailbox file exists" | tee -a "$LOG_FILE"
  echo "Contents:" | tee -a "$LOG_FILE"
  cat /etc/postfix/vmailbox | tee -a "$LOG_FILE"
else
  echo "ERROR: Postfix vmailbox file not found!" | tee -a "$LOG_FILE"
fi

# Check network connectivity
echo "\n--- Checking Network Connectivity ---" | tee -a "$LOG_FILE"
echo "Testing IMAP connection:" | tee -a "$LOG_FILE"
nc -zv localhost 143 2>&1 | tee -a "$LOG_FILE"
echo "Testing submission port:" | tee -a "$LOG_FILE"
nc -zv localhost 587 2>&1 | tee -a "$LOG_FILE"
echo "Testing HTTP connection:" | tee -a "$LOG_FILE"
nc -zv localhost 80 2>&1 | tee -a "$LOG_FILE"
echo "Testing HTTPS connection:" | tee -a "$LOG_FILE"
nc -zv localhost 443 2>&1 | tee -a "$LOG_FILE"

echo "\n--- Checking Apache Sites Enabled ---" | tee -a "$LOG_FILE"
ls -la /etc/apache2/sites-enabled/ | tee -a "$LOG_FILE"

# Run a quick manual telnet check for interactive troubleshooting
echo "\n--- Manual IMAP Check ---" | tee -a "$LOG_FILE"
echo "You can manually test login with these commands:\n" | tee -a "$LOG_FILE"
echo "1. telnet localhost 143" | tee -a "$LOG_FILE"
echo "2. a login $ADMIN_EMAIL your_password" | tee -a "$LOG_FILE"
echo "3. a logout" | tee -a "$LOG_FILE"

# Add option to try to fix common issues
echo "\n========================================================="
echo "            AUTOMATIC REPAIR SUGGESTIONS            "
echo "========================================================="

# Check for common issues and suggest fixes
FIXES_NEEDED=0

# Check if permissions are wrong on mailbox
if [ -d "$MAILDIR" ] && [ "$(stat -c '%U:%G' "$MAILDIR")" != "vmail:vmail" ]; then
  echo "[ISSUE] Mailbox directory permissions are incorrect" | tee -a "$LOG_FILE"
  echo "Fix: chown -R vmail:vmail $MAILDIR" | tee -a "$LOG_FILE"
  FIXES_NEEDED=1
fi

# Check if permissions are wrong on users file
if [ -f "/etc/dovecot/users" ] && [ "$(stat -c '%a' "/etc/dovecot/users")" != "600" ]; then
  echo "[ISSUE] Dovecot users file permissions are incorrect" | tee -a "$LOG_FILE"
  echo "Fix: chmod 600 /etc/dovecot/users" | tee -a "$LOG_FILE"
  FIXES_NEEDED=1
fi

# Check if default Apache site is still enabled
if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
  echo "[ISSUE] Default Apache site is still enabled" | tee -a "$LOG_FILE"
  echo "Fix: a2dissite 000-default.conf" | tee -a "$LOG_FILE"
  FIXES_NEEDED=1
fi

# Check if mail vhost is not enabled
if [ ! -f "/etc/apache2/sites-enabled/$MAIL_HOSTNAME.conf" ]; then
  echo "[ISSUE] Mail virtual host is not enabled" | tee -a "$LOG_FILE"
  echo "Fix: a2ensite $MAIL_HOSTNAME.conf" | tee -a "$LOG_FILE"
  FIXES_NEEDED=1
fi

# Offer to apply fixes
if [ $FIXES_NEEDED -eq 1 ]; then
  echo "\nWould you like to attempt automatic fixes for these issues? (y/n)"
  read -r APPLY_FIXES
  
  if [[ $APPLY_FIXES =~ ^[Yy]$ ]]; then
    echo "Applying fixes..." | tee -a "$LOG_FILE"
    
    # Fix mailbox permissions
    if [ -d "$MAILDIR" ] && [ "$(stat -c '%U:%G' "$MAILDIR")" != "vmail:vmail" ]; then
      echo "Fixing mailbox permissions..." | tee -a "$LOG_FILE"
      chown -R vmail:vmail "$MAILDIR"
    fi
    
    # Fix users file permissions
    if [ -f "/etc/dovecot/users" ] && [ "$(stat -c '%a' "/etc/dovecot/users")" != "600" ]; then
      echo "Fixing users file permissions..." | tee -a "$LOG_FILE"
      chmod 600 /etc/dovecot/users
      chown vmail:dovecot /etc/dovecot/users
    fi
    
    # Disable default Apache site
    if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
      echo "Disabling default Apache site..." | tee -a "$LOG_FILE"
      a2dissite 000-default.conf
    fi
    
    # Enable mail vhost
    if [ ! -f "/etc/apache2/sites-enabled/$MAIL_HOSTNAME.conf" ]; then
      echo "Enabling mail virtual host..." | tee -a "$LOG_FILE"
      a2ensite "$MAIL_HOSTNAME.conf"
    fi
    
    # Restart services
    echo "Restarting services..." | tee -a "$LOG_FILE"
    systemctl restart apache2
    systemctl restart dovecot
    systemctl restart postfix
    
    echo "Fixes applied. Please try logging in again." | tee -a "$LOG_FILE"
  else
    echo "No fixes applied." | tee -a "$LOG_FILE"
  fi
fi

# Offer to reset the password again
echo "\nWould you like to reset the admin password? (y/n)"
read -r RESET_PASSWORD

if [[ $RESET_PASSWORD =~ ^[Yy]$ ]]; then
  # Generate new password hash
  echo "Enter new password for $ADMIN_EMAIL:"
  read -s NEW_PASSWORD
  echo "Confirm new password:"
  read -s CONFIRM_PASSWORD
  
  if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    echo "Passwords do not match. Aborting." | tee -a "$LOG_FILE"
    exit 1
  fi
  
  PASS_HASH=$(doveadm pw -s SHA512-CRYPT -p "$NEW_PASSWORD")
  
  # Backup the users file
  cp /etc/dovecot/users /etc/dovecot/users.bak."$DATE_SUFFIX"
  
  # Update password in dovecot users file
  if grep -q "^$ADMIN_EMAIL:" /etc/dovecot/users; then
    sed -i "s|^$ADMIN_EMAIL:.*|$ADMIN_EMAIL:$PASS_HASH|" /etc/dovecot/users
  else
    echo "$ADMIN_EMAIL:$PASS_HASH" > /etc/dovecot/users
  fi
  
  # Set proper permissions
  chmod 600 /etc/dovecot/users
  chown vmail:dovecot /etc/dovecot/users
  
  # Restart Dovecot
  systemctl restart dovecot
  
  echo "Password reset. Please try logging in with the new password." | tee -a "$LOG_FILE"
fi

echo "\n--- Testing IMAP Login Directly ---" | tee -a "$LOG_FILE"
if [ -n "$NEW_PASSWORD" ]; then
  echo "Testing login with new password..." | tee -a "$LOG_FILE"
  {
    echo "a login \"$ADMIN_EMAIL\" \"$NEW_PASSWORD\""
    sleep 1
    echo "a logout"
  } | telnet localhost 143 2>&1 | tee -a "$LOG_FILE"
else
  echo "Password not reset. Skipping IMAP login test." | tee -a "$LOG_FILE"
fi

echo "\n========================================================="
echo "            TROUBLESHOOTING COMPLETE                 "
echo "========================================================="
echo "Results saved to: $LOG_FILE"
echo "Please review the log for any errors and try logging in again."
echo "If you're still having issues, please share this log file with support."
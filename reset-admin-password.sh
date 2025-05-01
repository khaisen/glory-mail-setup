#!/bin/bash
# Script to reset the admin password for mail server
# Run this script as root on your mail server

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Variables
DOMAIN="gloryeducationcenter.in"
ADMIN_EMAIL="admin@$DOMAIN"

# Prompt for new password
read -s -p "Enter new password for $ADMIN_EMAIL: " NEW_PASSWORD
echo ""
if [ -z "$NEW_PASSWORD" ]; then
  echo "Password cannot be empty"
  exit 1
fi

read -s -p "Confirm new password: " CONFIRM_PASSWORD
echo ""
if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
  echo "Passwords do not match"
  exit 1
fi

# Backup the users file
cp /etc/dovecot/users /etc/dovecot/users.bak

# Generate new password hash
PASS_HASH=$(doveadm pw -s SHA512-CRYPT -p "$NEW_PASSWORD")

# Check if the user already exists in the file
if grep -q "^$ADMIN_EMAIL:" /etc/dovecot/users; then
  # Update existing user
  sed -i "s|^$ADMIN_EMAIL:.*|$ADMIN_EMAIL:$PASS_HASH|" /etc/dovecot/users
  echo "Updated password for existing user $ADMIN_EMAIL"
else
  # Add new user if it doesn't exist
  echo "$ADMIN_EMAIL:$PASS_HASH" > /etc/dovecot/users
  echo "Created new user $ADMIN_EMAIL"
  
  # Ensure mailbox directory exists
  mkdir -p /var/mail/vhosts/$DOMAIN/admin/{cur,new,tmp}
  chown -R vmail:vmail /var/mail/vhosts/$DOMAIN/admin
  
  # Add to Postfix virtual mailbox file if not there
  if ! grep -q "^$ADMIN_EMAIL" /etc/postfix/vmailbox; then
    echo "$ADMIN_EMAIL $DOMAIN/admin/" >> /etc/postfix/vmailbox
    postmap /etc/postfix/vmailbox
  fi
fi

# Set proper permissions
chmod 600 /etc/dovecot/users
chown vmail:dovecot /etc/dovecot/users

# Restart Dovecot to apply changes
systemctl restart dovecot

echo "Password for $ADMIN_EMAIL has been reset."
echo "You can now log in at https://mail.$DOMAIN with the new password."
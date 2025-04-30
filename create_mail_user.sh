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
echo "They can now log in at https://mail.gloryeducationcenter.in"
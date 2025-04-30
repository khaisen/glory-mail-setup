#!/bin/bash

# === CONFIGURE ME ===
DOMAIN="gloryeducationcenter.in"
MAIL_SUBDOMAIN="mail.$DOMAIN"
HOSTNAME="$MAIL_SUBDOMAIN"
SELECTOR="mail"
MAIL_USER="glory"
MAIL_PASS="Glory@1234"
SSL_DIR="/etc/ssl/cloudflare"
DKIM_DIR="/etc/opendkim"
KEY_DIR="$DKIM_DIR/keys/$DOMAIN"

# === START SETUP ===
echo "[*] Updating system and setting hostname..."
apt update && apt upgrade -y
hostnamectl set-hostname "$HOSTNAME"

# === Install required packages ===
echo "[*] Installing mail packages..."
apt install postfix dovecot-core dovecot-imapd dovecot-pop3d opendkim opendkim-tools -y

# === Cloudflare SSL setup ===
echo "[*] Configuring Cloudflare SSL..."
mkdir -p $SSL_DIR

cat > "$SSL_DIR/cloudflare.crt" <<EOF
-----BEGIN CERTIFICATE-----
YOUR_SSL_CERT_CONTENT
-----END CERTIFICATE-----
EOF

cat > "$SSL_DIR/cloudflare.key" <<EOF
-----BEGIN PRIVATE KEY-----
YOUR_SSL_KEY_CONTENT
-----END PRIVATE KEY-----
EOF

chmod 600 $SSL_DIR/*

# === Postfix config ===
echo "[*] Configuring Postfix..."
postconf -e "myhostname = $MAIL_SUBDOMAIN"
postconf -e "myorigin = /etc/mailname"
postconf -e "mydestination = localhost, $DOMAIN, $MAIL_SUBDOMAIN"
postconf -e "mynetworks = 127.0.0.0/8"
postconf -e "relayhost ="
postconf -e "mailbox_size_limit = 0"
postconf -e "recipient_delimiter = +"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"

# SSL
postconf -e "smtpd_tls_cert_file=$SSL_DIR/cloudflare.crt"
postconf -e "smtpd_tls_key_file=$SSL_DIR/cloudflare.key"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_security_level=may"

# Milter (DKIM)
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 2"
postconf -e "smtpd_milters = inet:localhost:12301"
postconf -e "non_smtpd_milters = inet:localhost:12301"

# === Dovecot config ===
echo "[*] Configuring Dovecot..."
sed -i 's/^#ssl =.*/ssl = required/' /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^#ssl_cert =.*|ssl_cert = <$SSL_DIR/cloudflare.crt|" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^#ssl_key =.*|ssl_key = <$SSL_DIR/cloudflare.key|" /etc/dovecot/conf.d/10-ssl.conf

# === Create mail user ===
echo "[*] Creating local mail user..."
adduser --disabled-password --gecos "" $MAIL_USER
echo "$MAIL_USER:$MAIL_PASS" | chpasswd

# === OpenDKIM setup ===
echo "[*] Setting up OpenDKIM for $DOMAIN..."
mkdir -p "$KEY_DIR"
opendkim-genkey -D "$KEY_DIR" -d "$DOMAIN" -s "$SELECTOR"
chown -R opendkim:opendkim $DKIM_DIR

cat > "$DKIM_DIR/KeyTable" <<EOF
$SELECTOR._domainkey.$DOMAIN $DOMAIN:$SELECTOR:$KEY_DIR/$SELECTOR.private
EOF

cat > "$DKIM_DIR/SigningTable" <<EOF
*@${DOMAIN} $SELECTOR._domainkey.${DOMAIN}
EOF

cat > "$DKIM_DIR/TrustedHosts" <<EOF
127.0.0.1
localhost
*.${DOMAIN}
EOF

cat >> /etc/opendkim.conf <<EOF

# Mail DKIM config
AutoRestart             Yes
Syslog                  yes
LogWhy                  Yes
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:$DKIM_DIR/TrustedHosts
InternalHosts           refile:$DKIM_DIR/TrustedHosts
KeyTable                refile:$DKIM_DIR/KeyTable
SigningTable            refile:$DKIM_DIR/SigningTable
Socket                  inet:12301@localhost
PidFile                 /var/run/opendkim/opendkim.pid
UserID                  opendkim
EOF

# === Enable and restart services ===
echo "[*] Restarting services..."
systemctl restart postfix dovecot opendkim
systemctl enable postfix dovecot opendkim

# === Open firewall ports ===
echo "[*] Configuring firewall..."
ufw allow 22
ufw allow 25
ufw allow 587
ufw allow 143
ufw allow 993
ufw --force enable

# === OUTPUT DNS RECORDS ===
echo
echo "================= ADD THESE DNS RECORDS TO CLOUDFLARE ===================="
echo
echo "1. 🔐 DKIM Record (TXT)"
echo "Name: $SELECTOR._domainkey.$DOMAIN"
echo "Value:"
cat $KEY_DIR/$SELECTOR.txt
echo
echo "2. 🛡️ SPF Record (TXT)"
echo "Name: @"
echo "Value: v=spf1 mx -all"
echo
echo "3. 🔐 DMARC Record (TXT)"
echo "Name: _dmarc.$DOMAIN"
echo "Value: v=DMARC1; p=none; rua=mailto:postmaster@$DOMAIN"
echo
echo "========================================================================="
echo "[✅] Setup complete! You can now use $MAIL_USER@$DOMAIN via IMAP/SMTP."
echo "Don't forget to add the above TXT records to your Cloudflare DNS."

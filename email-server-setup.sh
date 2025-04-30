#!/bin/bash
# Full Email Server Setup Script
# Target OS: Ubuntu 22.04 LTS
# This script installs and configures Postfix, Dovecot, MySQL, OpenDKIM, and RainLoop

set -e

### 1. UPDATE SYSTEM ###
echo "[1/10] Updating system packages..."
apt update && apt upgrade -y

### 2. INSTALL DEPENDENCIES ###
echo "[2/10] Installing base packages..."
apt install -y curl wget gnupg2 software-properties-common lsb-release ca-certificates unzip

### 3. SET HOSTNAME AND HOSTS ###
echo "[3/10] Setting hostname..."
hostnamectl set-hostname mail.gloryeducationcenter.in
echo "127.0.0.1 mail.gloryeducationcenter.in mail" >> /etc/hosts

### 4. INSTALL MYSQL ###
echo "[4/10] Installing MySQL..."
apt install -y mysql-server
mysql_secure_installation <<EOF
n
y
y
y
y
EOF

### 5. CREATE DATABASE ###
echo "[5/10] Creating mail database..."
mysql -u root <<EOF
CREATE DATABASE mailserver;
CREATE USER 'mailuser'@'localhost' IDENTIFIED BY 'glory@123';
GRANT ALL PRIVILEGES ON mailserver.* TO 'mailuser'@'localhost';
FLUSH PRIVILEGES;

USE mailserver;

CREATE TABLE virtual_domains (
  id INT NOT NULL AUTO_INCREMENT,
  name VARCHAR(50) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE virtual_users (
  id INT NOT NULL AUTO_INCREMENT,
  domain_id INT NOT NULL,
  password VARCHAR(106) NOT NULL,
  email VARCHAR(100) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY email (email),
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE virtual_aliases (
  id INT NOT NULL AUTO_INCREMENT,
  domain_id INT NOT NULL,
  source VARCHAR(100) NOT NULL,
  destination VARCHAR(100) NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO virtual_domains (name) VALUES ('gloryeducationcenter.in');
INSERT INTO virtual_users (domain_id, password, email) VALUES (1, ENCRYPT('glory@123', CONCAT('
$6$', SUBSTRING(SHA(RAND()), -16))), 'glory@gloryeducationcenter.in');
EOF

### 6. INSTALL POSTFIX ###
echo "[6/10] Installing Postfix..."
DEBIAN_FRONTEND=noninteractive apt install -y postfix postfix-mysql
mkdir -p /etc/postfix/sql

cat > /etc/postfix/sql/mysql-virtual-domains.cf <<EOL
user = mailuser
password = glory@123
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOL

cat > /etc/postfix/sql/mysql-virtual-users.cf <<EOL
user = mailuser
password = glory@123
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s'
EOL

cat > /etc/postfix/sql/mysql-virtual-aliases.cf <<EOL
user = mailuser
password = glory@123
hosts = 127.0.0.1
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOL

### 7. INSTALL DOVECOT ###
echo "[7/10] Installing Dovecot..."
apt install -y dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql

adduser --system --group --home /var/mail/vmail vmail
mkdir -p /var/mail/vmail
chown -R vmail:vmail /var/mail/vmail
chmod -R 770 /var/mail/vmail

### 8. INSTALL OPENDKIM ###
echo "[8/10] Installing OpenDKIM..."
apt install -y opendkim opendkim-tools
mkdir -p /etc/opendkim/keys/gloryeducationcenter.in
cd /etc/opendkim/keys/gloryeducationcenter.in
opendkim-genkey -s mail -d gloryeducationcenter.in
chown -R opendkim:opendkim /etc/opendkim

cat > /etc/opendkim/key.table <<EOL
mail._domainkey.gloryeducationcenter.in gloryeducationcenter.in:mail:/etc/opendkim/keys/gloryeducationcenter.in/mail.private
EOL

cat > /etc/opendkim/signing.table <<EOL
*@gloryeducationcenter.in mail._domainkey.gloryeducationcenter.in
EOL

cat > /etc/opendkim/trusted.hosts <<EOL
127.0.0.1
localhost
gloryeducationcenter.in
EOL

### 9. INSTALL RAINLOOP ###
echo "[9/10] Installing RainLoop webmail..."
wget https://github.com/RainLoop/rainloop-webmail/releases/download/v1.17.0/rainloop-legacy-1.17.0.zip
unzip rainloop-legacy-1.17.0.zip -d /var/www/rainloop
chown -R www-data:www-data /var/www/rainloop
chmod -R 755 /var/www/rainloop

### 10. CONFIGURATION FILES PLACEHOLDERS ###
echo "[10/10] Creating config file placeholders..."

cat > /etc/nginx/sites-available/webmail.gloryeducationcenter.in <<EOL
server {
    listen 80;
    server_name webmail.gloryeducationcenter.in;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name webmail.gloryeducationcenter.in;

    root /var/www/rainloop;
    index index.php index.html;

    ssl_certificate /etc/ssl/cloudflare/cloudflare.crt;
    ssl_certificate_key /etc/ssl/cloudflare/cloudflare.key;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
    }

    location ~* ^/(data|config|\.ht|README|CHANGELOG|composer\.json) {
        deny all;
        return 404;
    }
}
EOL

ln -s /etc/nginx/sites-available/webmail.gloryeducationcenter.in /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Final instructions
echo "Setup completed!"
echo "✅ Configure your DNS in Cloudflare:"
echo "SPF:  v=spf1 mx ~all"
echo "DKIM: Use contents of /etc/opendkim/keys/gloryeducationcenter.in/mail.txt"
echo "DMARC: v=DMARC1; p=quarantine; rua=mailto:postmaster@gloryeducationcenter.in"
echo "🌐 Visit https://webmail.gloryeducationcenter.in to access your webmail."

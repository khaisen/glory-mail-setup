# Complete Mail Server Setup Guide for gloryeducationcenter.in

This guide provides comprehensive instructions for setting up a complete mail server with webmail access on your domain.

## Prerequisites

1. Ubuntu/Debian server (tested on Ubuntu 22.04 LTS)
2. Domain name (gloryeducationcenter.in)
3. Cloudflare account with access to your domain's DNS settings
4. Cloudflare Origin Certificates for your domain

## Step 1: Prepare Your Server

1. Connect to your server via SSH:
   ```bash
   ssh user@your-server-ip
   ```

2. Update the system:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

## Step 2: Prepare Cloudflare Certificates

1. Log in to your Cloudflare dashboard
2. Navigate to SSL/TLS > Origin Server
3. Create a new Origin Certificate:
   - Add hostnames: `gloryeducationcenter.in` and `*.gloryeducationcenter.in`
   - Select 15 years for validity
   - Create certificate

4. You'll receive two files:
   - Origin Certificate (PEM format)
   - Private Key (PEM format)

5. Save these files on your local machine for later use

## Step 3: Set Up the Mail Server

1. Create a project directory on your server:
   ```bash
   mkdir -p ~/mail-server-setup/certificates
   cd ~/mail-server-setup
   ```

2. Create a certificates directory and upload your Cloudflare certificates:
   - Upload your Origin Certificate as `certificates/origin-certificate.pem`
   - Upload your Private Key as `certificates/private-key.pem`

   You can use SCP to upload the files:
   ```bash
   scp /path/to/local/origin-certificate.pem user@your-server-ip:~/mail-server-setup/certificates/
   scp /path/to/local/private-key.pem user@your-server-ip:~/mail-server-setup/certificates/
   ```

3. Download the setup script:
   ```bash
   wget -O complete-mail-server-setup.sh https://raw.githubusercontent.com/yourusername/business_mail_server_setup/main/complete-mail-server-setup.sh
   ```

4. Edit the script to set your server IP address:
   ```bash
   nano complete-mail-server-setup.sh
   ```
   Change the line: `SERVER_IP="YOUR_SERVER_IP"` to your actual server IP address

5. Make the script executable:
   ```bash
   chmod +x complete-mail-server-setup.sh
   ```

6. Run the setup script:
   ```bash
   sudo ./complete-mail-server-setup.sh
   ```

7. Follow the prompts to enter and confirm an admin password

8. The script will:
   - Install all necessary packages
   - Configure Postfix, Dovecot, and OpenDKIM
   - Set up Roundcube webmail
   - Configure SSL using your Cloudflare certificates
   - Set up security features (Fail2ban, DKIM, SPF)
   - Create an admin email account
   - Generate DNS configuration instructions

## Step 4: Configure DNS Records in Cloudflare

After the script completes, it will display DNS records to add in Cloudflare. Add these records to your Cloudflare DNS configuration:

1. **MX Record**
   - Type: MX
   - Name: @ (root domain)
   - Priority: 10
   - Value: mail.gloryeducationcenter.in
   - TTL: Auto
   - Proxy status: DNS only (grey cloud - important!)

2. **A Record**
   - Type: A
   - Name: mail
   - Value: YOUR_SERVER_IP
   - TTL: Auto
   - Proxy status: DNS only (grey cloud)

3. **SPF Record**
   - Type: TXT
   - Name: @ (root domain)
   - Value: v=spf1 mx ip4:YOUR_SERVER_IP ~all
   - TTL: Auto
   - Proxy status: DNS only (grey cloud)

4. **DKIM Record**
   - Type: TXT
   - Name: mail._domainkey
   - Value: [VALUE FROM SCRIPT OUTPUT]
   - TTL: Auto
   - Proxy status: DNS only (grey cloud)

5. **DMARC Record**
   - Type: TXT
   - Name: _dmarc
   - Value: v=DMARC1; p=quarantine; rua=mailto:admin@gloryeducationcenter.in
   - TTL: Auto
   - Proxy status: DNS only (grey cloud)

**Important:** All email-related DNS records must use DNS only mode (grey cloud), not proxied mode (orange cloud).

## Step 5: Access Your Webmail

1. After DNS propagation (can take up to 24-48 hours), access your webmail at:
   ```
   https://mail.gloryeducationcenter.in
   ```

2. Log in with:
   - Username: admin@gloryeducationcenter.in
   - Password: [the password you set during installation]

## Step 6: Create Additional Email Accounts

To create additional email accounts, use the provided script:

```bash
sudo /usr/local/bin/add_mail_user.sh newuser@gloryeducationcenter.in password
```

The new user can then log in at https://mail.gloryeducationcenter.in with their email and password.

## Troubleshooting

If you encounter login issues, a diagnostic tool is available at:
```
https://mail.gloryeducationcenter.in/check-login.php
```

Common issues and solutions:

1. **Login Failed**
   - Check if the mail services are running: `sudo systemctl status postfix dovecot`
   - Verify the user exists: `sudo cat /etc/dovecot/users`
   - Check mailbox permissions: `sudo ls -la /var/mail/vhosts/gloryeducationcenter.in`

2. **Can't Connect to Webmail**
   - Verify DNS records are set correctly in Cloudflare
   - Check Apache configuration: `sudo systemctl status apache2`
   - Verify SSL certificate: `sudo ls -la /etc/cloudflare/certs/`

3. **OpenDKIM Issues**
   - Check OpenDKIM service: `sudo systemctl status opendkim`
   - If it fails to start: `sudo journalctl -xeu opendkim.service`

## Security Considerations

1. The mail server has basic security measures including:
   - Fail2ban to protect against brute force attacks
   - DKIM, SPF, and DMARC to prevent email spoofing
   - SSL/TLS encryption for all connections

2. Additional recommended security measures:
   - Set up regular backup of mail directories and configuration
   - Keep the server updated: `sudo apt update && sudo apt upgrade`
   - Consider adding a spam filter like SpamAssassin

## Maintenance

1. Regularly check the logs:
   ```bash
   sudo tail -f /var/log/mail.log
   sudo tail -f /var/log/apache2/roundcube_error.log
   ```

2. Monitor disk usage:
   ```bash
   sudo du -h --max-depth=1 /var/mail/vhosts
   ```

3. Keep an eye on service status:
   ```bash
   sudo systemctl status postfix dovecot apache2 opendkim
   ```

## Conclusion

You now have a fully functional email server with webmail access for your domain. Users can send and receive emails using the webmail interface, or configure desktop or mobile email clients using the following settings:

- **IMAP Server**: mail.gloryeducationcenter.in (Port 993, SSL/TLS)
- **SMTP Server**: mail.gloryeducationcenter.in (Port 587, STARTTLS)
- **Username**: [full email address]
- **Password**: [user's password]

Enjoy your new mail server!
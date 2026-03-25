#!/bin/bash
set -euxo pipefail

LOG_FILE="/var/log/user-data.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "===== User Data Script Started ====="

DOMAIN="test.vishnugaur.in"
EMAIL="nishanttdevops@gmail.com"
ANSIBLE_DIR="/opt/ansible"

########################################
# Update system & install required tools
########################################
apt-get update -y
apt-get upgrade -y

apt-get install -y \
    ansible \
    git \
    curl \
    certbot \
    python3-certbot-nginx \
    dnsutils \
    gnupg2 \
    ca-certificates \
    lsb-release

########################################
# Clone Ansible Repo
########################################
mkdir -p $ANSIBLE_DIR
cd $ANSIBLE_DIR

if [ ! -d ansible ]; then
    git clone https://github.com/vsmac/ansible.git
fi
cd ansible

########################################
# Ensure roles/nginx/templates exist
########################################
mkdir -p roles/nginx/templates

# index.html
cat <<'EOF' > roles/nginx/templates/index.html
<!DOCTYPE html>
<html>
<head>
<title>Nishant DevOps Server</title>
</head>
<body style="background:black;color:white;text-align:center">
<h1>🚀 NGINX + Ansible + Auto SSL Working</h1>
<p>Deployment Successful</p>
</body>
</html>
EOF

# default.conf (root domain only, with ACME challenge location)
cat <<EOF > roles/nginx/templates/default.conf
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/html;
    index index.html;

    # Allow Certbot ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        try_files \$uri \$uri/ /index.html?\$query_string;
    }

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

# nginx.conf template
cat <<'EOF' > roles/nginx/templates/nginx.conf
user www-data;                
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

########################################
# Force localhost execution in playbook
########################################
sed -i 's/hosts:.*/hosts: localhost/' nginx.yml || true

########################################
# Run Ansible Playbook (installs and configures nginx)
########################################
echo "Running Ansible Playbook..."
ansible-playbook nginx.yml -i localhost, -c local

########################################
# Validate & restart nginx
########################################
nginx -t
systemctl enable nginx
systemctl restart nginx

########################################
# Wait until DNS resolves to this server
########################################
echo "Waiting for DNS propagation..."
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

until dig +short $DOMAIN | grep -q "$PUBLIC_IP"; do
    echo "DNS not ready yet..."
    sleep 10
done
echo "DNS is ready!"

########################################
# Install SSL Automatically (root domain only)
########################################
echo "Running Certbot for SSL..."
certbot --nginx \
    -d $DOMAIN \
    --preferred-challenges http \
    --http-01-port 80 \
    --agree-tos \
    -m $EMAIL \
    --redirect \
    --non-interactive

########################################
# Enable auto-renewal
########################################
systemctl enable certbot.timer
systemctl start certbot.timer

########################################
# Final status check
########################################
systemctl status nginx --no-pager
certbot certificates

echo "===== Deployment Completed Successfully ====="
#!/bin/bash
set -ex

exec > >(tee /var/log/userdata.log) 2>&1

echo "===== 🚀 Starting deployment at $(date) ====="

########################################
# VARIABLES
########################################
APP_NAME="portfolio"
APP_DIR="/home/azureuser/$APP_NAME"
DOMAIN="test.vishnugaur.in"
EMAIL="rajagaur333@gmail.com"
USERNAME="rajagaur333"
PAT_TOKEN="${PAT_TOKEN}"

########################################
# 1️⃣ Update system & install dependencies
########################################
apt-get update
apt-get upgrade -y
apt-get install -y curl git nginx lsb-release certbot python3-certbot-nginx

########################################
# 2️⃣ Install Node.js (LTS)
########################################
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

########################################
# 3️⃣ Install PM2 globally
########################################
npm install -g pm2

########################################
# 4️⃣ Fix ownership
########################################
chown -R azureuser:azureuser /home/azureuser

########################################
# 5️⃣ Clone or update repo
########################################
if [ -d "$APP_DIR" ]; then
    echo "♻️ Repo exists, pulling latest..."
    cd "$APP_DIR"
    git reset --hard
    git clean -fd
    git pull origin main
else
    echo "📥 Cloning repo..."
    cd /home/azureuser
    git clone "https://${USERNAME}:${PAT_TOKEN}@dev.azure.com/rajagaur333/Devops_Learning/_git/portfolio" "$APP_DIR"
fi

# 🔥 FIX PERMISSIONS (MANDATORY)
sudo chown -R azureuser:azureuser $APP_DIR

########################################
# 6️⃣ Build app (as azureuser)
########################################
sudo -u azureuser bash << 'EOF'

export HOME=/home/azureuser
export PM2_HOME=/home/azureuser/.pm2

cd /home/azureuser/portfolio

echo "🧹 Cleaning old build..."
rm -rf .next

echo "📦 Installing dependencies..."
npm install --no-audit --no-fund

echo "🏗️ Building app..."
npm run build

EOF

########################################
# 7️⃣ Start app with PM2 (as azureuser)
########################################
sudo -u azureuser bash << 'EOF'

export HOME=/home/azureuser
export PM2_HOME=/home/azureuser/.pm2

cd /home/azureuser/portfolio

echo "🛑 Stopping old app..."
pm2 delete portfolio || true

echo "🚀 Starting app..."
pm2 start npm --name portfolio -i 1 -- start

echo "💾 Saving PM2..."
pm2 save

EOF

########################################
# 8️⃣ Setup PM2 startup
########################################
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u azureuser --hp /home/azureuser
systemctl enable pm2-azureuser

########################################
# 9️⃣ Configure Nginx
########################################
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

nginx -t
systemctl restart nginx
systemctl enable nginx

########################################
# 1️⃣1️⃣ Setup SSL with Certbot
########################################
PUBLIC_IP=$(curl -s ifconfig.me)
echo "🌐 Waiting for DNS to point to $PUBLIC_IP..."
until dig +short $DOMAIN | grep -q "$PUBLIC_IP"; do
  echo "DNS not ready yet..."
  sleep 15
done

sudo certbot --nginx -d $DOMAIN --agree-tos -m $EMAIL --redirect --non-interactive || true
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

########################################
# 🔟 Final Status
########################################
echo "📊 PM2 Status:"
sudo -u azureuser pm2 status

echo "🌐 Testing app..."
sleep 5
curl -I http://localhost:3000 || true

echo "===== ✅ Deployment completed at $(date) ====="
echo "🌐 App running on: https://$DOMAIN"
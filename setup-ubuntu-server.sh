#!/bin/bash

set -e

echo "🔧 Starting Ubuntu Server Setup with Performance Tuning..."

# 1. Set timezone to Dhaka, Bangladesh (+6 GMT)
echo "Setting timezone to Asia/Dhaka..."
sudo timedatectl set-timezone Asia/Dhaka

# 2. Update system packages
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# ===============================================
# INSTALL CORE SOFTWARES
# ===============================================
echo "🚀 Installing Core Software Components..."

# Install required packages
echo "Installing required packages..."
sudo apt install -y software-properties-common apt-transport-https ca-certificates curl gnupg lsb-release

# Add PHP 8.3 repository
echo "Adding PHP 8.3 repository..."
LC_ALL=C.UTF-8 sudo add-apt-repository ppa:ondrej/php -y
sudo apt update

# Add NodeJS repository
echo "Adding NodeJS repository..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -

# Install all core packages: nginx, PHP 8.3, MySQL, Node.js, certbot
echo "Installing nginx, PHP 8.3, MySQL, Node.js, certbot, and other core dependencies..."
sudo apt install -y nginx php8.3 php8.3-fpm php8.3-mysql php8.3-xml php8.3-gd php8.3-curl php8.3-zip php8.3-mbstring php8.3-bcmath php8.3-intl php8.3-readline php8.3-dev php8.3-cli php8.3-sqlite3 php8.3-opcache php8.3-xsl php8.3-imagick mysql-server nodejs certbot python3-certbot-nginx unzip git

# Install development packages required for OpenSwoole compilation
echo "Installing development packages for OpenSwoole..."
sudo apt install -y build-essential libcurl4-openssl-dev libssl-dev zlib1g-dev libpcre3-dev libnghttp2-dev

# Install Composer
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer

# Install PHP OpenSwoole (successor to Swoole)
echo "Installing PHP OpenSwoole..."
sudo pecl install openswoole
echo "extension=openswoole.so" | sudo tee /etc/php/8.3/mods-available/openswoole.ini
sudo phpenmod openswoole

# Enable additional PHP modules
echo "Enabling PHP modules..."
sudo phpenmod bcmath curl gd imagick intl mbstring mysqli opcache sqlite3 xml xsl zip

# ===============================================
# INSTALL MONITORING AND OTHER TOOLS
# ===============================================
echo "📊 Installing Monitoring Tools and Security Components..."

# Install system monitoring tools and fail2ban
echo "Installing monitoring tools and fail2ban..."
sudo apt install -y fail2ban htop iftop nethogs vnstat nload iotop dstat ncdu tree net-tools

# Configure vnstat for network monitoring
echo "Configuring vnstat for network monitoring..."
sudo systemctl enable vnstat
sudo systemctl start vnstat

# Configure fail2ban
echo "Configuring fail2ban..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Create fail2ban jail configuration for SSH
sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

sudo systemctl restart fail2ban

# Create monitoring aliases for easy system monitoring
echo "Creating monitoring aliases..."
sudo tee -a /home/ubuntu/.bashrc > /dev/null <<'EOF'

# System Monitoring Aliases
alias bandwidth='vnstat -i eth0'
alias netspeed='nload -m'
alias netconnections='nethogs'
alias netreal='iftop'
alias diskusage='ncdu'
alias processes='htop'
alias iostat='iotop'
alias systemstats='dstat'
alias netstat='ss -tuln'
EOF

# ===============================================
# CONFIGURE GIT
# ===============================================
echo "🔧 Configuring Git..."

# Verify git installation
if ! command -v git &> /dev/null; then
    echo "Installing git..."
    sudo apt install -y git
fi

# Set up basic git configuration
echo "Setting up basic git configuration..."
sudo -u ubuntu git config --global init.defaultBranch main
sudo -u ubuntu git config --global pull.rebase false
sudo -u ubuntu git config --global core.editor nano

echo "Git version: $(git --version)"
echo "Note: Configure your git user with:"
echo "  git config --global user.name 'Your Name'"
echo "  git config --global user.email 'your.email@example.com'"

# ===============================================
# TUNE SYSTEM FOR BETTER PERFORMANCE
# ===============================================
echo "⚡ Starting Nginx Performance Tuning..."
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%F-%T)
sudo cp nginx.conf /etc/nginx/nginx.conf

echo "⚡ Starting System Performance Tuning..."

# === SYSCTL SETTINGS ===
echo "📄 Updating /etc/sysctl.conf..."
sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%F-%T)

sudo tee -a /etc/sysctl.conf > /dev/null <<EOF

# Custom performance tuning
fs.file-max = 2097152
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 32768 60999
EOF

sudo sysctl -p

# === LIMITS SETTINGS ===
echo "📄 Updating /etc/security/limits.conf..."
sudo tee -a /etc/security/limits.conf > /dev/null <<EOF

# Increase open file limits
* soft nofile 262144
* hard nofile 262144
root soft nofile 262144
root hard nofile 262144
EOF

# PAM
echo "📄 Ensuring PAM config includes limits..."
for file in /etc/pam.d/common-session /etc/pam.d/common-session-noninteractive; do
    if ! grep -q "pam_limits.so" "$file"; then
        echo "session required pam_limits.so" | sudo tee -a "$file" > /dev/null
    fi
done

# === SYSTEMD OVERRIDES ===
echo "📄 Configuring systemd limits..."
sudo mkdir -p /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/limits.conf > /dev/null <<EOF
[Manager]
DefaultLimitNOFILE=262144
EOF

sudo mkdir -p /etc/systemd/user.conf.d
sudo tee /etc/systemd/user.conf.d/limits.conf > /dev/null <<EOF
[Manager]
DefaultLimitNOFILE=262144
EOF

# === CONFIGURE SCHEDULING AND CLEANUP AUTOMATION ===
echo "⏰ Configuring system scheduling and cleanup automation..."

# Disable default certbot auto-renewal and set up custom schedule
echo "Configuring certbot auto-renewal..."
sudo systemctl stop certbot.timer 2>/dev/null || true
sudo systemctl disable certbot.timer 2>/dev/null || true

# Create custom certbot renewal script
sudo tee /usr/local/bin/certbot-renewal.sh > /dev/null <<'EOF'
#!/bin/bash
/usr/bin/certbot renew --quiet --no-self-upgrade --post-hook "systemctl reload nginx"
EOF

sudo chmod +x /usr/local/bin/certbot-renewal.sh

# Set up system maintenance cron jobs
echo "Setting up system maintenance cron jobs..."
sudo crontab -l > system_cron 2>/dev/null || true

# Add certbot renewal at exactly 2:30 AM daily
echo "30 2 * * * /usr/local/bin/certbot-renewal.sh" >> system_cron

# Add memory cleanup at 3:00 AM daily
echo "0 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >> system_cron

# Add comprehensive log cleanup at 3:30 AM every Friday
echo "30 3 * * 5 find /var/log -type f \( -name '*.log' -o -name '*.log.*' -o -name 'syslog*' -o -name 'auth.log*' -o -name 'kern.log*' -o -name 'mail.log*' -o -name 'debug*' -o -name 'messages*' -o -name 'daemon.log*' -o -name 'user.log*' -o -name 'lpr.log*' -o -name 'mail.info*' -o -name 'mail.warn*' -o -name 'mail.err*' -o -name 'news.crit*' -o -name 'news.err*' -o -name 'news.notice*' -o -name 'uucp.log*' -o -name 'bootstrap.log*' -o -name 'dmesg*' -o -name 'faillog*' -o -name 'lastlog*' -o -name 'wtmp*' -o -name 'btmp*' \) -exec truncate -s 0 {} \;" >> system_cron

# Add server restart at 4:00 AM every Friday
echo "0 4 * * 5 /sbin/reboot" >> system_cron

sudo crontab system_cron
rm system_cron

# === VERIFY PERFORMANCE SETTINGS ===
echo "✅ Verifying applied performance values:"
echo "ulimit: $(ulimit -n)"
echo "fs.file-max: $(cat /proc/sys/fs/file-max)"
echo "somaxconn: $(cat /proc/sys/net/core/somaxconn)"
echo "netdev_max_backlog: $(cat /proc/sys/net/core/netdev_max_backlog)"
echo "tcp_max_syn_backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"
echo "ip_local_port_range: $(cat /proc/sys/net/ipv4/ip_local_port_range)"

# Verify PHP installation and modules
echo ""
echo "✅ Verifying PHP 8.3 installation and modules:"
php --version
echo ""
echo "PHP modules installed:"
php -m

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "=== INSTALLED CORE SOFTWARE ==="
echo "• Nginx - Web server"
echo "• PHP 8.3 - with all required modules"
echo "• MySQL Server - Database server"
echo "• Node.js 20.x - JavaScript runtime"
echo "• Composer - PHP dependency manager"
echo "• Certbot - SSL certificate management"
echo "• OpenSwoole - High-performance PHP extension"
echo ""
echo "=== INSTALLED MONITORING TOOLS ==="
echo "• htop          - Interactive process viewer (run: htop)"
echo "• iftop         - Real-time network bandwidth monitor (run: sudo iftop)"
echo "• nethogs       - Network usage by process (run: sudo nethogs)"
echo "• vnstat        - Network statistics (run: vnstat -i eth0)"
echo "• nload         - Network load monitor (run: nload)"
echo "• iotop         - I/O usage by process (run: sudo iotop)"
echo "• dstat         - System statistics (run: dstat)"
echo "• ncdu          - Disk usage analyzer (run: ncdu)"
echo "• net-tools     - Network utilities (netstat, ifconfig)"
echo "• fail2ban      - Intrusion prevention system"
echo ""
echo "=== USEFUL MONITORING COMMANDS ==="
echo "• bandwidth     - Show network statistics"
echo "• netspeed      - Show real-time network speed"
echo "• netconnections- Show network usage by process"
echo "• netreal       - Show real-time network connections"
echo "• bandwidth-live- Live bandwidth monitoring"
echo "• diskusage     - Analyze disk usage"
echo "• processes     - Show running processes"
echo "• iostat        - Show I/O statistics"
echo "• systemstats   - Show system statistics"
echo ""
echo "=== PERFORMANCE TUNING APPLIED ==="
echo "• File descriptor limits increased to 262,144"
echo "• Network performance optimized"
echo "• System limits configured"
echo "• PAM limits enabled"
echo "• Systemd limits configured"
echo "• Automated scheduling configured:"
echo "  - Certbot renewal: 2:30 AM daily"
echo "  - Memory cleanup: 3:00 AM daily"
echo "  - Log cleanup: 3:30 AM every Friday"
echo "  - System reboot: 4:00 AM every Friday"
echo ""
echo "=== PHP 8.3 MODULES INSTALLED ==="
echo "All required PHP modules have been installed including:"
echo "• OpenSwoole (modern successor to Swoole)"
echo "• ImageMagick (imagick)"
echo "• All core PHP modules and extensions"
echo ""
echo "=== SECURITY CONFIGURATION ==="
echo "Fail2ban status:"
sudo fail2ban-client status
echo ""
echo "Certbot auto-renewal status:"
echo "Custom certbot renewal scheduled at 2:30 AM daily"
echo "Default certbot timer: $(sudo systemctl is-enabled certbot.timer 2>/dev/null || echo 'disabled')"
echo ""
echo "⚠️  Reboot is recommended to apply all systemd-level changes and performance tuning."
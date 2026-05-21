#!/bin/bash

# ============================================================
# Automatic Galene Video Conference Server Installer
# For Ubuntu 24.04 (Noble)
# ============================================================

set -e

# Colors for Beauty 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }


# exec is root or no 
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. Use: sudo ./install_galene.sh"
fi


# user variable
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"admin123"}
GALENE_PORT=${GALENE_PORT:-8443}
USE_ARVAN_MIRROR=${USE_ARVAN_MIRROR:-true}
GROUP_NAME=${GROUP_NAME:-"company"}

info "Starting Galène installation..."
info "Port: $GALENE_PORT"
info "Default group: $GROUP_NAME"
info "Admin password: $ADMIN_PASSWORD"



# set mirror arvan for higre speed
if [ "$USE_ARVAN_MIRROR" = true ]; then
    info "Setting apt mirror to mirror.arvancloud.ir..."
    cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d)
    cat > /etc/apt/sources.list <<EOF
deb http://mirror.arvancloud.ir/ubuntu noble main restricted universe multiverse
deb http://mirror.arvancloud.ir/ubuntu noble-updates main restricted universe multiverse
deb http://mirror.arvancloud.ir/ubuntu noble-backports main restricted universe multiverse
deb http://mirror.arvancloud.ir/ubuntu noble-security main restricted universe multiverse
EOF
    mkdir -p /etc/apt/sources.list.d/backup
    mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/backup/ 2>/dev/null || true
    mv /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/backup/ 2>/dev/null || true
fi

info "Updating package list..."
apt update

info "Installing prerequisites (git, golang, build-essential, unzip)..."
apt install -y git golang-go build-essential unzip

cd /opt
if [ -d "/opt/galene" ]; then
    warn "/opt/galene already exists. Creating backup..."
    mv /opt/galene /opt/galene.bak.$(date +%Y%m%d%H%M%S)
fi

# Download source code with fallback methods
info "Downloading Galène source code..."
if wget -q --show-progress https://github.com/jech/galene/archive/refs/heads/master.zip -O master.zip; then
    info "Download successful via direct GitHub."
elif wget -q --show-progress https://ghproxy.net/https://github.com/jech/galene/archive/refs/heads/master.zip -O master.zip; then
    info "Download successful via ghproxy.net."
else
    warn "wget failed, trying git clone..."
    git clone https://github.com/jech/galene.git
    cd galene
fi

if [ -f master.zip ]; then
    unzip -q master.zip
    mv galene-master galene
    cd galene
fi

info "Compiling Galène..."
chown -R $SUDO_USER:$SUDO_USER /opt/galene 2>/dev/null || true
export GOPROXY=https://goproxy.ir,direct
CGO_ENABLED=0 go build -ldflags='-s -w'

if [ ! -f "./galene" ]; then
    error "Compilation failed."
fi
success "Galène binary built successfully."

info "Creating default group '$GROUP_NAME' with admin user..."
mkdir -p /opt/galene/groups
cat > /opt/galene/groups/${GROUP_NAME}.json <<EOF
{
  "users": {
    "admin": {
      "password": "$ADMIN_PASSWORD",
      "permissions": "op"
    }
  }
}
EOF

if [ "$GALENE_PORT" != "8443" ]; then
    info "Changing port to $GALENE_PORT..."
    cat > /opt/galene/config.json <<EOF
{
    "https": ":$GALENE_PORT",
    "turn": {"private": true}
}
EOF
else
    info "Using default port 8443 (no config.json)"
fi


info "Creating systemd service..."
cat > /etc/systemd/system/galene.service <<EOF
[Unit]
Description=Galène videoconference server
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
WorkingDirectory=/opt/galene
ExecStart=/opt/galene/galene
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable galene
systemctl start galene

sleep 2
if systemctl is-active --quiet galene; then
    success "Galène service started successfully."
else
    error "Service failed to start. Check logs: journalctl -u galene"
fi

if command -v ufw &> /dev/null && ufw status | grep -q active; then
    info "Opening port $GALENE_PORT in UFW..."
    ufw allow ${GALENE_PORT}/tcp
    ufw reload
fi

SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)

clear
success "=========================================="
success "Galene installation completed successfully!"
success "=========================================="
echo ""
echo -e "${GREEN}Access URL for group '$GROUP_NAME':${NC}"
echo -e "  ${BLUE}https://${SERVER_IP}:${GALENE_PORT}/group/${GROUP_NAME}/${NC}"
echo ""
echo -e "${GREEN}Admin login:${NC}"
echo -e "  Username: ${YELLOW}admin${NC}"
echo -e "  Password: ${YELLOW}${ADMIN_PASSWORD}${NC}"
echo ""
echo -e "${GREEN}Service management:${NC}"
echo -e "  Status:   ${BLUE}sudo systemctl status galene${NC}"
echo -e "  Stop:     ${BLUE}sudo systemctl stop galene${NC}"
echo -e "  Start:    ${BLUE}sudo systemctl start galene${NC}"
echo -e "  Logs:     ${BLUE}sudo journalctl -u galene -f${NC}"
echo ""
echo -e "${YELLOW}Note: Ignore SSL certificate warning (self-signed).${NC}"
echo -e "${YELLOW}To add users, edit /opt/galene/groups/${GROUP_NAME}.json${NC}"
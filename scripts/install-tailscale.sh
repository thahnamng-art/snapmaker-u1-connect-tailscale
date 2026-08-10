#!/bin/bash
# Install Tailscale on Snapmaker U1 (Buildroot Linux ARM64)
# Usage: ./install-tailscale.sh
# This script downloads and installs Tailscale with userspace networking support

# ============================================================
# CONFIGURATION - Edit these values if needed
# ============================================================
TAILSCALE_VERSION="1.80.0"
ARCH="arm64"
# ============================================================

set -e

echo "=== Installing Tailscale $TAILSCALE_VERSION ($ARCH) on Snapmaker U1 ==="

# Step 1: Check if already installed
echo ""
echo "Step 1: Checking existing installation..."
if [ -f /usr/bin/tailscale ] && [ -f /usr/bin/tailscaled ]; then
    echo "OK: Tailscale already installed at /usr/bin/"
    echo "    tailscale version: $(tailscale version 2>&1 || echo 'unknown')"
else
    echo "INFO: Tailscale not found, will install..."
fi

# Step 2: Download Tailscale
echo ""
echo "Step 2: Downloading Tailscale $TAILSCALE_VERSION..."
URL="https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${ARCH}.tgz"
echo "Source: $URL"

wget -q "$URL" -O /tmp/tailscale.tgz || {
    echo "ERROR: Failed to download from $URL"
    echo "Check your internet connection or try a different version."
    exit 1
}
echo "OK: Downloaded to /tmp/tailscale.tgz"

# Step 3: Extract and install
echo ""
echo "Step 3: Extracting and installing..."
tar -xzf /tmp/tailscale.tgz -C /tmp/
DIR="/tmp/tailscale_${TAILSCALE_VERSION}_${ARCH}"

if [ ! -d "$DIR" ]; then
    echo "ERROR: Extraction directory not found: $DIR"
    ls /tmp/tailscale_* 2>/dev/null
    exit 1
fi

cp "$DIR/tailscale" /usr/bin/
cp "$DIR/tailscaled" /usr/bin/
chmod +x /usr/bin/tailscale /usr/bin/tailscaled
echo "OK: Installed to /usr/bin/tailscale and /usr/bin/tailscaled"

# Step 4: Create TUN device
echo ""
echo "Step 4: Creating /dev/net/tun device..."
mkdir -p /dev/net
mknod /dev/net/tun c 10 200 2>/dev/null || true
chmod 0666 /dev/net/tun
echo "OK: /dev/net/tun ready"

# Step 5: Start tailscaled
echo ""
echo "Step 5: Starting tailscaled (userspace-networking)..."
pkill tailscaled 2>/dev/null || true
sleep 1
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
sleep 3

if pgrep -x tailscaled > /dev/null; then
    echo "OK: tailscaled started (PID: $(pgrep -x tailscaled))"
else
    echo "ERROR: Failed to start tailscaled"
    tailscaled --tun=userspace-networking 2>&1 | head -20
    exit 1
fi

# Step 6: Setup auto-start in rc.local
echo ""
echo "Step 6: Configuring auto-start on boot..."

RC_LOCAL="/etc/rc.local"
if [ -f "$RC_LOCAL" ]; then
    # Check if tailscaled line already exists
    if ! grep -q "tailscaled" "$RC_LOCAL"; then
        # Remove any old tailscaled lines and add proper one
        sed -i '/tailscaled/d' "$RC_LOCAL"
        cat >> "$RC_LOCAL" << 'EOF'

# Tailscale auto-start
mknod /dev/net/tun c 10 200 2>/dev/null
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
EOF
        echo "OK: Added tailscaled to $RC_LOCAL"
    else
        echo "INFO: tailscaled already in $RC_LOCAL"
    fi
else
    echo "Creating $RC_LOCAL..."
    cat > "$RC_LOCAL" << 'EOF'
#!/bin/bash
# Tailscale auto-start
mknod /dev/net/tun c 10 200 2>/dev/null
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
EOF
    chmod +x "$RC_LOCAL"
    echo "OK: Created $RC_LOCAL"
fi

# Step 7: Connect to Tailscale network
echo ""
echo "Step 7: Connecting to Tailscale network..."
echo "IMPORTANT: You will need to authenticate at the URL shown below"
tailscale up 2>&1 || echo "NOTE: Run 'tailscale up' manually if auth is needed"

# Step 8: Show status
echo ""
echo "=== INSTALLATION COMPLETE ==="
echo ""
tailscale status 2>&1 || echo "Run 'tailscale up' to connect"
echo ""
echo "Tailscale IP: $(tailscale ip -4 2>/dev/null)"
echo ""
echo "Tailscale will:"
echo "  - Run in background"
echo "  - Persist when you close SSH/CMD"
echo "  - Auto-start on boot"
echo ""
echo "You can now close the SSH session safely."
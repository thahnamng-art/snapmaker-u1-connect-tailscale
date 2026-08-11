#!/bin/bash
# Full Tailscale install with persistence on Snapmaker U1
# Usage: ./install-tailscale-persist.sh
# This script installs Tailscale and ensures it survives reboot
# by putting binaries in /usr/bin and creating an init script
# in /etc/init.d (persists via overlay upperdir /oem/overlay/upper)

# ============================================================
# CONFIGURATION
# ============================================================
TAILSCALE_VERSION="1.80.0"
ARCH="arm64"
# ============================================================

set -e

echo "=============================================="
echo "  Tailscale Install with Persistence"
echo "=============================================="
echo ""

# ========== Step 1: Download ==========
echo "[1] Downloading Tailscale $TAILSCALE_VERSION..."
URL="https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${ARCH}.tgz"
echo "Source: $URL"
# Use curl since busybox wget doesn't support HTTPS
curl -sSL -o /tmp/tailscale.tgz "$URL" || {
    echo "ERROR: Download failed"
    exit 1
}
echo "OK: Downloaded"

# ========== Step 2: Extract ==========
echo "[2] Extracting..."
tar -xzf /tmp/tailscale.tgz -C /tmp/
DIR="/tmp/tailscale_${TAILSCALE_VERSION}_${ARCH}"

if [ ! -d "$DIR" ]; then
    echo "ERROR: Extract dir not found"
    exit 1
fi
echo "OK: Extracted to $DIR"

# ========== Step 3: Install binaries ==========
echo "[3] Installing binaries..."
cp "$DIR/tailscale" /usr/bin/
cp "$DIR/tailscaled" /usr/bin/
chmod +x /usr/bin/tailscale /usr/bin/tailscaled
echo "OK: Installed"

# ========== Step 4: Create state dir ==========
echo "[4] Creating state directory..."
mkdir -p /var/lib/tailscale
echo "OK: /var/lib/tailscale created"

# ========== Step 5: Create TUN device ==========
echo "[5] Creating /dev/net/tun..."
mkdir -p /dev/net
mknod /dev/net/tun c 10 200 2>/dev/null || true
chmod 0666 /dev/net/tun
echo "OK: /dev/net/tun ready"

# ========== Step 6: Create init script (PERSISTS) ==========
echo "[6] Creating init script /etc/init.d/S99tailscaled..."
cat > /etc/init.d/S99tailscaled << 'EOF'
#!/bin/sh
# Tailscale auto-start for Snapmaker U1
# Persists across reboots via overlay upperdir

START=99

# Ensure tun device exists
mkdir -p /dev/net
mknod /dev/net/tun c 10 200 2>/dev/null
chmod 0666 /dev/net/tun

# Start tailscaled
if ! pgrep -x tailscaled > /dev/null 2>&1; then
    nohup /usr/bin/tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state > /dev/null 2>&1 &
    echo "Started tailscaled"
fi
EOF
chmod +x /etc/init.d/S99tailscaled
echo "OK: init script created"

# ========== Step 7: Start tailscaled ==========
echo "[7] Starting tailscaled..."
pkill tailscaled 2>/dev/null || true
sleep 1
nohup /usr/bin/tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state > /dev/null 2>&1 &
sleep 3

if pgrep -x tailscaled > /dev/null; then
    echo "OK: tailscaled running (PID: $(pgrep -x tailscaled))"
else
    echo "ERROR: Failed to start tailscaled"
    exit 1
fi

# ========== Step 8: Connect (non-blocking) ==========
echo "[8] Connecting to Tailscale (non-blocking)..."
# Use timeout to avoid blocking; if already authenticated, uses saved state
timeout 15 tailscale up > /dev/null 2>&1 || true
sleep 2

# Show status
echo ""
echo "=== INSTALL COMPLETE ==="
tailscale status 2>&1 || echo "Not connected yet - run: tailscale up"
echo ""
echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'N/A')"
echo ""
echo "IMPORTANT: Sync filesystem now to persist changes..."
sync
echo "OK: Files synced"
echo ""
echo "Test reboot persistence: reboot && check if tailscaled auto-starts"
echo ""

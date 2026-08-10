#!/bin/bash
# Setup Tailscale to persist on Snapmaker U1 (Buildroot Linux ARM64)
# This script makes Tailscale run in background and survive SSH/CMD closure

echo "=== Setting up persistent Tailscale on Snapmaker U1 ==="

# Step 1: Create /dev/net/tun device if not exists
echo "Step 1: Creating /dev/net/tun device..."
mkdir -p /dev/net
mknod /dev/net/tun c 10 200 2>/dev/null || true
chmod 0666 /dev/net/tun
echo "OK: /dev/net/tun ready"

# Step 2: Stop any running tailscaled processes first
echo "Step 2: Stopping any existing tailscaled processes..."
pkill tailscaled 2>/dev/null || true
sleep 2

# Step 3: Start tailscaled as a background daemon with userspace networking
echo "Step 3: Starting tailscaled in background (userspace-networking)..."
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
sleep 3

# Step 4: Check if tailscaled started successfully
echo "Step 4: Checking tailscaled status..."
if pgrep -x tailscaled > /dev/null; then
    echo "OK: tailscaled started successfully (PID: $(pgrep -x tailscaled))"
else
    echo "FAILED: Could not start tailscaled"
    exit 1
fi

# Step 5: Connect to Tailscale network if not already connected
echo "Step 5: Connecting to Tailscale network..."
tailscale up

# Step 6: Show Tailscale status
echo ""
echo "=== Tailscale Status ==="
tailscale status
echo ""
echo "Tailscale IP: $(tailscale ip -4)"

# Step 7: Setup auto-start on boot via rc.local
echo ""
echo "Step 7: Setting up auto-start on boot..."
RC_LOCAL="/etc/rc.local"

# Create the rc.local entry with proper nohup and userspace-networking
RC_ENTRY="
# Tailscale auto-start
(mknod /dev/net/tun c 10 200 2>/dev/null || true)
(nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &)
"

if [ -f "$RC_LOCAL" ]; then
    # Check if tailscaled line already exists
    if ! grep -q "tailscaled" "$RC_LOCAL"; then
        echo -e "$RC_ENTRY" >> "$RC_LOCAL"
        echo "OK: Added tailscaled to $RC_LOCAL"
    else
        echo "OK: tailscaled already configured in $RC_LOCAL"
        echo "--- Current rc.local content ---"
        cat "$RC_LOCAL"
    fi
else
    echo "Creating $RC_LOCAL..."
    cat > "$RC_LOCAL" << 'EOF'
#!/bin/bash
# Tailscale auto-start
(mknod /dev/net/tun c 10 200 2>/dev/null || true)
(nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &)
EOF
    chmod +x "$RC_LOCAL"
    echo "OK: Created $RC_LOCAL"
fi

echo ""
echo "=== Setup Complete ==="
echo "Tailscale will now:"
echo "  - Run in background"
echo "  - Persist when you close SSH/CMD"
echo "  - Auto-start on boot"
echo ""
echo "You can now close the SSH session safely."
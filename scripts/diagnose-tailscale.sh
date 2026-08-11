#!/bin/bash
# Diagnose and fix Tailscale on Snapmaker U1 after reboot
# Usage: ./diagnose-tailscale.sh
# This script checks and auto-fixes Tailscale issues

echo "=============================================="
echo "  Tailscale Diagnosis & Auto-Fix"
echo "=============================================="
echo ""

FIXED=0

# ============================================
# Check 1: /dev/net/tun device
# ============================================
echo "[1] Checking /dev/net/tun device..."
if [ -e /dev/net/tun ]; then
    echo "  -> OK: /dev/net/tun exists"
else
    echo "  -> MISSING: Creating /dev/net/tun..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null
    chmod 0666 /dev/net/tun
    if [ -e /dev/net/tun ]; then
        echo "  -> FIXED: /dev/net/tun created"
        FIXED=1
    else
        echo "  -> ERROR: Could not create /dev/net/tun"
    fi
fi
echo ""

# ============================================
# Check 2: tailscaled binary exists
# ============================================
echo "[2] Checking tailscaled binary..."
if [ -f /usr/bin/tailscaled ]; then
    echo "  -> OK: /usr/bin/tailscaled exists"
else
    echo "  -> ERROR: tailscaled not found at /usr/bin/tailscaled"
    echo "  -> Please run install-tailscale.sh first"
    exit 1
fi
echo ""

# ============================================
# Check 3: tailscaled process running
# ============================================
echo "[3] Checking tailscaled process..."
if pgrep -x tailscaled > /dev/null 2>&1; then
    echo "  -> OK: tailscaled running (PID: $(pgrep -x tailscaled))"
else
    echo "  -> NOT RUNNING: Starting tailscaled..."
    nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
    sleep 3
    if pgrep -x tailscaled > /dev/null 2>&1; then
        echo "  -> FIXED: tailscaled started (PID: $(pgrep -x tailscaled))"
        FIXED=1
    else
        echo "  -> ERROR: Failed to start tailscaled"
        echo "  -> Try running manually: tailscaled --tun=userspace-networking"
    fi
fi
echo ""

# ============================================
# Check 4: /etc/rc.local auto-start config
# ============================================
echo "[4] Checking /etc/rc.local auto-start..."
RC_LOCAL="/etc/rc.local"
NEED_RC_FIX=0

if [ -f "$RC_LOCAL" ]; then
    if grep -q "tailscaled" "$RC_LOCAL"; then
        echo "  -> OK: tailscaled configured in rc.local"
        grep -n "tailscaled" "$RC_LOCAL"
    else
        echo "  -> NOT CONFIGURED: Adding tailscaled to rc.local..."
        NEED_RC_FIX=1
    fi
else
    echo "  -> rc.local NOT FOUND: Creating..."
    NEED_RC_FIX=1
fi

if [ $NEED_RC_FIX -eq 1 ]; then
    # Create proper rc.local
    cat > "$RC_LOCAL" << 'EOF'
#!/bin/bash
# Tailscale auto-start
mknod /dev/net/tun c 10 200 2>/dev/null
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
EOF
    chmod +x "$RC_LOCAL"
    echo "  -> FIXED: rc.local updated"
    cat "$RC_LOCAL"
    FIXED=1
fi
echo ""

# ============================================
# Check 5: Tailscale connection status
# ============================================
echo "[5] Checking Tailscale connection..."
if command -v tailscale > /dev/null 2>&1; then
    STATUS=$(tailscale status 2>&1)
    IP=$(tailscale ip -4 2>/dev/null)
    
    if [ -n "$IP" ]; then
        echo "  -> OK: Connected with IP: $IP"
        echo "$STATUS"
    else
        echo "  -> NOT CONNECTED: Running 'tailscale up'..."
        echo "  -> NOTE: You may need to authenticate at the URL shown"
        tailscale up 2>&1
        sleep 2
        IP=$(tailscale ip -4 2>/dev/null)
        if [ -n "$IP" ]; then
            echo "  -> FIXED: Connected with IP: $IP"
            FIXED=1
        else
            echo "  -> WARNING: Not connected yet. Run 'tailscale up' manually"
        fi
    fi
else
    echo "  -> ERROR: tailscale command not found"
fi
echo ""

# ============================================
# Summary
# ============================================
echo "=============================================="
if [ $FIXED -eq 1 ]; then
    echo "  RESULT: Issues found and FIXED"
else
    echo "  RESULT: All checks passed - no issues found"
fi
echo "=============================================="
echo ""
echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'Not connected')"
echo ""
echo "If IP is still not working, try:"
echo "  1. Check network: ping 100.101.102.103 (Tailscale DNS)"
echo "  2. Run 'tailscale up' manually"
echo "  3. Check Tailscale admin console for device status"
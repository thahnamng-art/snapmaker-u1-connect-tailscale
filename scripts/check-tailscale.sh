#!/bin/bash
# Check Tailscale status on Snapmaker U1
# Usage: ./check-tailscale.sh
# This script shows the current state of Tailscale on the device

echo "=== Tailscale Status Check ==="
echo ""

# Check 1: Is tailscaled running?
echo "[1] tailscaled process:"
if pgrep -a tailscaled > /dev/null 2>&1; then
    pgrep -a tailscaled
    echo "  -> RUNNING ✓"
else
    echo "  -> NOT RUNNING ✗"
    echo "  -> Start it with: nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &"
fi
echo ""

# Check 2: Is /dev/net/tun available?
echo "[2] /dev/net/tun device:"
if [ -e /dev/net/tun ]; then
    echo "  -> EXISTS ✓"
else
    echo "  -> MISSING ✗"
    echo "  -> Create it with: mknod /dev/net/tun c 10 200"
fi
echo ""

# Check 3: rc.local configuration
echo "[3] /etc/rc.local auto-start:"
if [ -f /etc/rc.local ]; then
    if grep -q "tailscaled" /etc/rc.local; then
        echo "  -> CONFIGURED ✓"
        grep -n "tailscaled" /etc/rc.local
    else
        echo "  -> NOT CONFIGURED ✗"
        echo "  -> Add to /etc/rc.local: nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &"
    fi
else
    echo "  -> rc.local NOT FOUND ✗"
fi
echo ""

# Check 4: Tailscale connection status
echo "[4] Tailscale connection:"
if command -v tailscale > /dev/null 2>&1; then
    tailscale status 2>&1 || echo "  -> Not connected. Run 'tailscale up'"
    echo ""
    IP=$(tailscale ip -4 2>/dev/null)
    if [ -n "$IP" ]; then
        echo "  -> IP: $IP ✓"
    fi
else
    echo "  -> tailscale command NOT FOUND ✗"
    echo "  -> Install with: ./install-tailscale.sh"
fi
echo ""

echo "=== Check Complete ==="
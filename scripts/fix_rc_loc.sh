#!/bin/bash
# Fix rc.local on Snapmaker U1 - use nohup for tailscaled
echo "=== Fixing /etc/rc.local ==="

# Create new rc.local content
cat > /etc/rc.local << 'EOF'
#!/bin/bash
# Tailscale auto-start
mknod /dev/net/tun c 10 200 2>/dev/null
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
EOF

chmod +x /etc/rc.local
echo "--- RC.LOCAL UPDATED ---"
cat /etc/rc.local

echo ""
echo "=== Restarting tailscaled with nohup ==="
pkill tailscaled 2>/dev/null
sleep 1
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
sleep 3

echo "--- TAILSCALED PROCESS ---"
pgrep -a tailscaled

echo ""
echo "=== Tailscale Status ==="
tailscale status 2>&1
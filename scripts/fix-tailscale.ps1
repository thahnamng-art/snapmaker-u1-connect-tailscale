# PowerShell script to fix Tailscale persistence on Snapmaker U1
# Usage: .\fix-tailscale.ps1
# This script fixes /etc/rc.local on Snapmaker U1 to use nohup for tailscaled

# ============================================================
# CONFIGURATION - Edit these values if needed
# ============================================================
$PLINK_PATH = "$env:TEMP\plink.exe"        # Path to plink.exe
$PLINK_URL  = "https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe"
$TARGET_IP  = "192.168.1.81"               # Snapmaker U1 IP address
$SSH_USER   = "root"                       # SSH username
$SSH_PASS   = "snapmaker"                  # SSH password
# ============================================================

# Check if plink.exe exists, if not download it
if (-not (Test-Path $PLINK_PATH)) {
    Write-Host "plink.exe not found. Downloading from PuTTY..."
    try {
        Invoke-WebRequest -Uri $PLINK_URL -OutFile $PLINK_PATH -UseBasicParsing
        Write-Host "OK: Downloaded plink.exe to $PLINK_PATH"
    } catch {
        Write-Host "ERROR: Failed to download plink.exe. Please download manually from:"
        Write-Host "  $PLINK_URL"
        Write-Host "  Save it to: $PLINK_PATH"
        exit 1
    }
}

Write-Host "=== Fixing Tailscale persistence on Snapmaker U1 ==="
Write-Host "Target: $SSH_USER@$TARGET_IP"

# Accept host key first
echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP "echo connected" 2>&1

# Step 1: Fix rc.local - replace content with nohup version
Write-Host "`nStep 1: Fixing /etc/rc.local..."
$cmd1 = 'printf "#!/bin/bash\n# Tailscale auto-start\nmknod /dev/net/tun c 10 200 2>/dev/null\nnohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &\n" > /etc/rc.local && chmod +x /etc/rc.local && echo "--- RC.LOCAL FIXED ---" && cat /etc/rc.local'

echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP $cmd1 2>&1

# Step 2: Kill old tailscaled and restart with nohup
Write-Host "`nStep 2: Restarting tailscaled with nohup..."
$cmd2 = 'pkill tailscaled; sleep 1; nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &; sleep 3; echo "--- TAILSCALED PROCESS ---"; pgrep -a tailscaled'

echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP $cmd2 2>&1

# Step 3: Check tailscale status
Write-Host "`nStep 3: Checking Tailscale status..."
$cmd3 = 'tailscale status 2>&1'

echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP $cmd3 2>&1

Write-Host ""
Write-Host "=== DONE ==="
Write-Host "Tailscale is now persistent. You can close the SSH session safely."
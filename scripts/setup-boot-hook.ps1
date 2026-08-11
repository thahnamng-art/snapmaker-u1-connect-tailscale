# Setup boot hook on Snapmaker U1 to auto-start Tailscale
# Usage: .\setup-boot-hook.ps1
# Problem: rcS is read from SquashFS BEFORE overlay mount, so modifying
# rcS in upper layer has no effect. Instead, we hook into S99_bootcontrol
# which is called AFTER overlay is mounted (VFS resolves to upper layer).

# ============================================================
# CONFIGURATION
# ============================================================
$PLINK_PATH = "$env:TEMP\plink.exe"
$PLINK_URL  = "https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe"
$TARGET_IP  = "192.168.1.81"
$SSH_USER   = "root"
$SSH_PASS   = "snapmaker"
# ============================================================

# Check plink
if (-not (Test-Path $PLINK_PATH)) {
    Write-Host "plink.exe not found. Downloading..."
    try {
        Invoke-WebRequest -Uri $PLINK_URL -OutFile $PLINK_PATH -UseBasicParsing
    } catch {
        Write-Host "ERROR: Failed to download plink.exe"
        exit 1
    }
}

# Accept host key
echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP "echo connected" 2>&1

# ============================================================
# Step 1: Remove rcS override (no longer needed)
# ============================================================
Write-Host "Step 1: Removing rcS override from upper layer..."
$cmd1 = "rm -f /oem/overlay/upper/etc/init.d/rcS && echo 'rcS override removed'"
echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP $cmd1 2>&1

# ============================================================
# Step 2: Create S99_bootcontrol hook in upper layer
# ============================================================
Write-Host "Step 2: Creating S99_bootcontrol hook..."

$hookScript = @'
#!/bin/sh
# S99_bootcontrol hook - overrides lower layer version
# This file is in overlay upper, so it's resolved AFTER overlay mount.
# It triggers S99tailscaled at the end of boot sequence.

DEBUG_LOG="/etc/tailscale-init-debug.log"

case "$1" in
    start)
        echo "=== S99_bootcontrol hook start at $(date) ===" >> $DEBUG_LOG
        if [ -x /etc/init.d/S99tailscaled ]; then
            echo "Triggering S99tailscaled start..." >> $DEBUG_LOG
            /etc/init.d/S99tailscaled start &
        else
            echo "S99tailscaled not found!" >> $DEBUG_LOG
        fi
        ;;
    stop)
        if [ -x /etc/init.d/S99tailscaled ]; then
            /etc/init.d/S99tailscaled stop
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        ;;
esac
'@

# Build bash command to write hook file
$bashCmd = @"
cat > /oem/overlay/upper/etc/init.d/S99_bootcontrol << 'HOOKEOF'
$hookScript
HOOKEOF
chmod 755 /oem/overlay/upper/etc/init.d/S99_bootcontrol
sync
echo '=== HOOK CREATED ==='
cat /oem/overlay/upper/etc/init.d/S99_bootcontrol
"@
$bashCmd = $bashCmd.Replace("`r`n", "`n")

$process = New-Object System.Diagnostics.Process
$process.StartInfo.FileName = $PLINK_PATH
$process.StartInfo.Arguments = "-ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP bash"
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.RedirectStandardInput = $true
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$process.StartInfo.CreateNoWindow = $true
$process.Start()
$process.StandardInput.Write($bashCmd)
$process.StandardInput.Close()
$output = $process.StandardOutput.ReadToEnd()
$err = $process.StandardError.ReadToEnd()
$process.WaitForExit()

Write-Host "OUTPUT:"
Write-Host $output
if ($err) {
    Write-Host "ERROR:"
    Write-Host $err
}
Write-Host "EXIT CODE: $($process.ExitCode)"

# ============================================================
# Step 3: Verify
# ============================================================
Write-Host ""
Write-Host "Step 3: Verifying..."
$cmd3 = "ls -la /oem/overlay/upper/etc/init.d/S99_bootcontrol; echo '---'; ls -la /oem/overlay/upper/etc/init.d/rcS 2>&1"
echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP $cmd3 2>&1

Write-Host ""
Write-Host "=== SETUP COMPLETE ==="
Write-Host "Ready for reboot test."
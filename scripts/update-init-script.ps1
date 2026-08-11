# Update S99tailscaled init script on Snapmaker U1
# Usage: .\update-init-script.ps1
# This script updates the init script to handle start/stop/restart properly

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

# Create the init script content
$initScript = @'
#!/bin/sh
# Tailscale auto-start for Snapmaker U1
# Persists across reboots via overlay upperdir

# Debug log - persists in /etc via overlay
DEBUG_LOG="/etc/tailscale-init-debug.log"

echo "=== S99tailscaled called at $(date) ===" >> $DEBUG_LOG
echo "Args: $@" >> $DEBUG_LOG

case "$1" in
    start|"")
        echo "Starting tailscaled..." >> $DEBUG_LOG

        # Ensure tun device exists
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200 2>/dev/null
        chmod 0666 /dev/net/tun
        echo "tun device ready" >> $DEBUG_LOG

        # Start tailscaled with setsid to detach from session
        if ! pgrep -x tailscaled > /dev/null 2>&1; then
            /usr/bin/setsid /usr/bin/tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state > /dev/null 2>&1 &
            echo "tailscaled started (PID: $!)" >> $DEBUG_LOG
        else
            echo "tailscaled already running (PID: $(pgrep -x tailscaled))" >> $DEBUG_LOG
        fi

        # Wait for network, with retry up to 30s
        i=0
        while [ $i -lt 10 ]; do
            sleep 3
            i=$((i+1))
            # Check if tailscaled is running and connected
            if pgrep -x tailscaled > /dev/null 2>&1; then
                IP=$(/usr/bin/tailscale ip -4 2>/dev/null)
                if [ -n "$IP" ]; then
                    echo "Tailscale connected: $IP" >> $DEBUG_LOG
                    echo "Tailscale connected: $IP"
                    break
                fi
            fi
        done
        echo "Start sequence complete" >> $DEBUG_LOG
        ;;
    stop)
        pkill tailscaled 2>/dev/null
        echo "Stopped tailscaled"
        ;;
    restart)
        pkill tailscaled 2>/dev/null
        sleep 1
        /usr/bin/setsid /usr/bin/tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state > /dev/null 2>&1 &
        echo "Restarted tailscaled"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        ;;
esac
'@

# Build the bash command to write the file
$bashCmd = "cat > /etc/init.d/S99tailscaled << 'INITEOF'`n" + $initScript + "`nINITEOF`nchmod +x /etc/init.d/S99tailscaled && sync && echo '=== UPDATED ===' && cat /etc/init.d/S99tailscaled"
# Convert CRLF to LF - critical for Linux heredocs
$bashCmd = $bashCmd.Replace("`r`n", "`n")

# Run via plink
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
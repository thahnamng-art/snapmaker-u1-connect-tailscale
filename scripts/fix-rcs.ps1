# Fix rcS on Snapmaker U1 to run S99tailscaled after overlay mount
# Usage: .\fix-rcs.ps1
# Problem: rcS expands glob /etc/init.d/S??* BEFORE overlay is mounted,
# so S99tailscaled (stored in overlay upper) is never run during boot.
# Solution: Create new rcS in overlay upper that re-scans after overlay mount.

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

# First, get the current rcS content to preserve it
Write-Host "Getting current rcS content..."
$getCmd = "cat /etc/init.d/rcS"
$process = New-Object System.Diagnostics.Process
$process.StartInfo.FileName = $PLINK_PATH
$process.StartInfo.Arguments = "-ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP `"cat /etc/init.d/rcS`""
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$process.StartInfo.CreateNoWindow = $true
$process.Start()
$output = $process.StandardOutput.ReadToEnd()
$err = $process.StandardError.ReadToEnd()
$process.WaitForExit()
Write-Host "Current rcS:"
Write-Host $output

# The new rcS content - optimized re-scan approach from Gemini
# Re-scans for new scripts appearing after overlay mount (S01aoverlayfs)
$newRcS = @'
#!/bin/sh

# Start all init scripts in /etc/init.d
# executing them in numerical order.
# Preserves original logic: .sh scripts are sourced, others are executed.
for i in /etc/init.d/S??* ; do
    # Ignore dangling symlinks (if any).
    [ ! -f "$i" ] && continue

    case "$i" in
        *.sh)
            # Source shell script for speed.
            (
                trap - INT QUIT TSTP
                set start
                . $i
            )
            ;;
        *)
            # No sh extension, so fork subprocess.
            $i start
            ;;
    esac

    # After S01aoverlayfs runs, re-scan for new scripts that appeared
    # in the overlay upper layer (e.g. S99tailscaled)
    if [ "$i" = "/etc/init.d/S01aoverlayfs" ]; then
        for late_script in /etc/init.d/S??* ; do
            # Skip scripts already run (S00*, S01*)
            case "$late_script" in
                /etc/init.d/S00*|/etc/init.d/S01*) continue ;;
            esac

            # Run any script not in the original glob list
            [ -x "$late_script" ] && $late_script start
        done
        # Exit old loop since re-scan loop ran all remaining services
        break
    fi
done
'@

# Write the new rcS to overlay upper so it persists and overrides lower
Write-Host "Writing new rcS to overlay upper..."
$bashCmd = @"
cat > /oem/overlay/upper/etc/init.d/rcS << 'RCSEOF'
$newRcS
RCSEOF
chmod 755 /oem/overlay/upper/etc/init.d/rcS
sync
echo '=== RC.S UPDATED IN OVERLAY UPPER ==='
cat /oem/overlay/upper/etc/init.d/rcS
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
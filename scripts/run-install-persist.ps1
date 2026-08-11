# Run install-tailscale-persist.sh on Snapmaker U1 via plink
# Usage: .\run-install-persist.ps1
# This script pipes install-tailscale-persist.sh content through plink to run on the U1

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

# Accept host key first
echo y | & $PLINK_PATH -ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP "echo connected" 2>&1

Write-Host "=== Installing Tailscale with persistence on $SSH_USER@$TARGET_IP ==="
Write-Host "NOTE: This will take a few minutes (download + extract + install)"
Write-Host ""

# Read the bash script and convert CRLF to LF (Linux line endings)
$content = [System.IO.File]::ReadAllText('install-tailscale-persist.sh')
$content = $content.Replace("`r`n", "`n")

# Run the install script via plink
$process = New-Object System.Diagnostics.Process
$process.StartInfo.FileName = $PLINK_PATH
$process.StartInfo.Arguments = "-ssh -l $SSH_USER -pw $SSH_PASS -no-antispoof $TARGET_IP bash"
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.RedirectStandardInput = $true
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$process.StartInfo.CreateNoWindow = $true
$process.Start()

$process.StandardInput.WriteLine($content)
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

if ($process.ExitCode -eq 0) {
    Write-Host ""
    Write-Host "=== INSTALL COMPLETE ==="
} else {
    Write-Host ""
    Write-Host "=== FAILED ==="
    Write-Host "Something went wrong. Check the error output above."
}
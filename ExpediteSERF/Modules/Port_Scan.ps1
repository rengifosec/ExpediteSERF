# ------------------------------
# Run Nmap Scan on Local Machine
# ------------------------------

# Define paths relative to the script's directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define log file
$LogPath = Join-Path -Path $ScriptRoot -ChildPath "Logs\"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath }
$LogFile = Join-Path -Path $LogPath -ChildPath "Port_Scan.log"

# Function to log messages
Function Log-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    $logEntry | Out-File -FilePath $LogFile -Append
}

# Clean Header with Subtle Accents
Log-Message "Starting Nmap Intense Port Scan"
Write-Host "`n==================================" -ForegroundColor Magenta
Write-Host "  Running " -NoNewline
Write-Host "Nmap - Intense Port Scan" -ForegroundColor Cyan
Write-Host "----------------------------------" -ForegroundColor Magenta

# Get local IPv4 address (Exclude Loopback & Virtual Adapters)
$LocalIP = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -notmatch "Loopback|Virtual" -and $_.PrefixOrigin -in ("Manual", "Dhcp") } |
    Select-Object -ExpandProperty IPAddress -First 1

if ($LocalIP) {
    Log-Message "Scanning local machine at: $LocalIP"
    Write-Host "  Scanning local machine at: " -NoNewline
    Write-Host "$LocalIP" -ForegroundColor Cyan

    # Check if Nmap is installed
    $NmapPath = (Get-Command nmap -ErrorAction SilentlyContinue).Source
    if ($NmapPath) {
        # Run Nmap scan
        $NmapResult = & nmap -T5 -A $LocalIP 2>$null | Out-String

        # Extract ports
        $Ports = $NmapResult -split "`n" | Where-Object { $_ -match "^[0-9]+/(tcp|udp)" }

        # Display results
        if ($Ports.Count -gt 0) {
            Log-Message "Nmap Scan Results (Ports Found)"
            Write-Host "`n  Nmap Scan Results " -NoNewline
            Write-Host "(Ports Found)" -ForegroundColor Cyan -NoNewline
            Write-Host "  "
            Write-Host "----------------------------------" -ForegroundColor Magenta

            # Process each port entry
            foreach ($line in $Ports) {
                if ($line -match "open") {
                    Write-Host "  $line" -ForegroundColor Cyan  # Open ports → Cyan
                    Log-Message "Open Port: $line"
                } elseif ($line -match "filtered") {
                    Write-Host "  $line" -ForegroundColor Red   # Filtered ports → Red
                    Log-Message "Filtered Port: $line"
                } else {
                    Write-Host "  $line"  # Default color for unknown states
                    Log-Message "Unknown Port State: $line"
                }
            }
        } else {
            Log-Message "No open or filtered ports detected."
            Write-Host "`nNo open or filtered ports detected." -ForegroundColor Green
        }
    } else {
        Log-Message "Nmap is not installed or not found in PATH." "ERROR"
        Write-Host "`nNmap is not installed or not found in PATH." -ForegroundColor Red
    }
} else {
    Log-Message "Could not retrieve the local IPv4 address." "ERROR"
    Write-Host "`nCould not retrieve the local IPv4 address." -ForegroundColor Red
}

# Footer with Accents
Write-Host "==================================" -ForegroundColor Magenta
Log-Message "Nmap Intense Port Scan completed"

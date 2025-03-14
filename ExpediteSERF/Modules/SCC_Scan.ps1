# Define paths relative to the script's directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootPath = Split-Path -Parent $ScriptRoot

# Load configuration file
$configFile = Join-Path -Path $RootPath -ChildPath "config.ini"
$configContent = Get-Content $configFile | Where-Object { $_ -notmatch '^\s*;|^\s*$' }
$config = $configContent | ConvertFrom-StringData

# Define the path to the SCAP Compliance Checker Command Line tool (CSCC)
$CSCCPath = $config.SCC_SCANNER_PATH

# Define the correct path to SCC Options File
$OptionsFile = $config.OPTIONS_FILE_PATH

# Define the path to SCC Sessions folder
$SessionFolder = $config.SESSION_FOLDER_PATH

# Define log file
$LogPath = Join-Path -Path $ScriptRoot -ChildPath "Logs\"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath }
$LogFile = Join-Path -Path $LogPath -ChildPath "SCC_Scan.log"

# Function to log messages
Function Write-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    $logEntry | Out-File -FilePath $LogFile -Append
    switch ($Level) {
        "INFO" { Write-Host "  $timestamp [" -NoNewline; Write-Host "$Level" -ForegroundColor Yellow -NoNewline; Write-Host "] $Message" }
        "SUCCESS" { Write-Host "  $timestamp [" -NoNewline; Write-Host "$Level" -ForegroundColor Green -NoNewline; Write-Host "] $Message" }
        "ERROR" { Write-Host "  $timestamp [" -NoNewline; Write-Host "$Level" -ForegroundColor Red -NoNewline; Write-Host "] $Message" }
        default { Write-Host $logEntry }
    }
}

# Verify CSCC exists
if (!(Test-Path $CSCCPath)) {
    Write-Message "Error: SCAP Compliance Checker CLI (cscc.exe) not found." "ERROR"
    Write-Host "Error: SCAP Compliance Checker CLI (cscc.exe) not found." -ForegroundColor Red
    exit 1
}

# Verify options.xml exists
if (!(Test-Path $OptionsFile)) {
    Write-Message "Error: SCC Options file not found at $OptionsFile" "ERROR"
    Write-Host "Error: SCC Options file not found at $OptionsFile" -ForegroundColor Red
    exit 1
}

# Clean & Styled Header with Subtle Accents
# Write-Message "Starting SCAP Compliance Scan"
Write-Host "===========================================" -ForegroundColor Magenta
Write-Host "  Starting " -NoNewline
Write-Host "SCAP Compliance Scan" -ForegroundColor Cyan -NoNewline
Write-Host "  "
Write-Host "===========================================" -ForegroundColor Magenta

# Start SCC scan in quiet mode (-q) to suppress all output
$Process = Start-Process -FilePath $CSCCPath -ArgumentList "-o `"$OptionsFile`" -q" -NoNewWindow -PassThru

# Simple Scanning Animation with Overwriting
$Frames = @("  Scanning PC.  ", "  Scanning PC.. ", "  Scanning PC...")  # Spaces at end ensure clearing old text
$FrameIndex = 0

while (!$Process.HasExited) {
    Write-Host ("`r" + $Frames[$FrameIndex]) -NoNewline  # Overwrites previous text
    Start-Sleep -Milliseconds 500  # Smooth transition speed
    $FrameIndex = ($FrameIndex + 1) % $Frames.Length
}

# Move to a new line after animation completes
Write-Host "`r  Finalizing Report..." -ForegroundColor Cyan
Start-Sleep -Seconds 2  # Simulate processing delay

# Get the latest session folder
$LatestSession = Get-ChildItem -Path $SessionFolder -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($LatestSession) {
    Write-Message "Report saved to: $LatestSession" "INFO"
} else {
    Write-Message "SCAP scan ran, but no new session files were detected." "ERROR"
    Write-Host "`rSCAP scan ran, but no new session files were detected." -ForegroundColor Red
}

# Footer with Accents
Write-Message "Completed SCAP Compliance Scan" "SUCCESS"

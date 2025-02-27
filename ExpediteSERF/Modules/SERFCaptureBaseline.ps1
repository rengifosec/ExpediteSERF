##################################################################################
# Written By: Jason Wheeler
# Purpose: Capture Installed Patches, Programs, Groups, Services, and Local Accounts. 
#          This allows you to do a before-and-after comparison to ensure software
#          doesn't change your baseline.
# Version: 2.0
#
# Modified for ExpediteSERF by Alejandro Rengifo
##################################################################################

# Declaring Functions
Function GetHotfix {
    Get-Hotfix
}

Function GetInstalledPrograms {
    Get-WmiObject -Class Win32_Product
}

Function GetLocalGroups {
    net localgroup
}

Function GetServices {
    Get-WmiObject win32_service | Select Name, Displayname, State, StartMode | Sort State, Name
}

Function GetLocalAccounts {
    wmic useraccount list full
}

# Define paths relative to the script's directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootPath = Split-Path -Parent $ScriptRoot
$ResultsPath = Join-Path -Path $ScriptRoot -ChildPath "ScriptResults\Results"
$LogPath = Join-Path -Path $ScriptRoot -ChildPath "Logs\"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath }
$LogFile = Join-Path -Path $LogPath -ChildPath "SERFCaptureBaseline.log"

# Load configuration file
$configFile = Join-Path -Path $RootPath -ChildPath "config.ini"
$configContent = Get-Content $configFile | Where-Object { $_ -notmatch '^\s*;|^\s*$' }
$config = $configContent | ConvertFrom-StringData

# Function to log messages
Function Log-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    $logEntry | Out-File -FilePath $LogFile -Append
    Write-Host "  $logEntry"
}

# Clean Header with Subtle Accents
# Log-Message "Starting SERF Baseline Capture"
Write-Host "`n==================================" -ForegroundColor Magenta
Write-Host "  Capturing " -NoNewline
Write-Host "SERF Baseline Results" -ForegroundColor Cyan -NoNewline
Write-Host "  "
Write-Host "----------------------------------" -ForegroundColor Magenta

# Call Functions and Produce Text Files
try {
    $GetLocalGroups = GetLocalGroups
    $GetLocalGroups | Out-File (Join-Path -Path $ResultsPath -ChildPath 'GetLocalGroups.txt')
    Log-Message "Captured Local Groups"

    $GetServices = GetServices
    $GetServices | Out-File (Join-Path -Path $ResultsPath -ChildPath 'GetServices.txt')
    Log-Message "Captured Services"

    $GetInstalledPrograms = GetInstalledPrograms
    $GetInstalledPrograms | Out-File (Join-Path -Path $ResultsPath -ChildPath 'InstalledPrograms.txt')
    Log-Message "Captured Installed Programs"

    $GetHotFix = GetHotFix
    $GetHotFix | Out-File (Join-Path -Path $ResultsPath -ChildPath 'HotFix.txt')
    Log-Message "Captured Hotfixes"

    $GetLocalAccounts = GetLocalAccounts
    $GetLocalAccounts | Out-File (Join-Path -Path $ResultsPath -ChildPath 'GetLocalAccounts.txt')
    Log-Message "Captured Local Accounts"
} catch {
    Log-Message "Error: $_" "ERROR"
    Write-Host "Error: $_" -ForegroundColor Red
}

# Footer with Accents
Write-Host "----------------------------------" -ForegroundColor Magenta
Log-Message "Completed SERF Baseline Capture"
Write-Host "==================================" -ForegroundColor Magenta

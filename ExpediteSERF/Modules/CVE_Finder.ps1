# Define the path to new_programs.txt
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path  
$ResultsPath = Join-Path -Path $ScriptRoot -ChildPath "ScriptResults"
$NewProgramsFile = Join-Path -Path $ResultsPath -ChildPath "new_programs.txt"
$CVEOutputFile = Join-Path -Path $ResultsPath -ChildPath "cve_results.txt"
$LogPath = Join-Path -Path $ScriptRoot -ChildPath "Logs\"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath }
$LogFile = Join-Path -Path $LogPath -ChildPath "CVE_Finder.log"

# Function to log messages
Function Log-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    $logEntry | Out-File -FilePath $LogFile -Append
    Write-Host $logEntry
}

# Check if new_programs.txt exists
if (!(Test-Path $NewProgramsFile)) {
    Log-Message "Error: new_programs.txt not found. Ensure it exists in ScriptResults." "ERROR"
    Write-Host "Error: new_programs.txt not found. Ensure it exists in ScriptResults." -ForegroundColor Red
    exit 1
}

# Clean Header with Subtle Accents
Log-Message "Starting CVE Finder"
Write-Host "`n==================================" -ForegroundColor Magenta
Write-Host "  Running " -NoNewline
Write-Host "CVE Finder" -ForegroundColor Cyan
Write-Host "  "
Write-Host "----------------------------------" -ForegroundColor Magenta

# Read installed programs
$Programs = @()
$CurrentProgram = @{}

Get-Content $NewProgramsFile | ForEach-Object {
    if ($_ -match "^\s*$") {
        if ($CurrentProgram.Count -gt 0) {
            $Programs += New-Object PSObject -Property $CurrentProgram
            $CurrentProgram = @{}
        }
    } elseif ($_ -match "^\s*([^:]+)\s*:\s*(.*)$") {
        $CurrentProgram[$matches[1].Trim()] = $matches[2].Trim()
    }
}

if ($CurrentProgram.Count -gt 0) {
    $Programs += New-Object PSObject -Property $CurrentProgram
}

# Clear CVE results file before writing new results
if (Test-Path $CVEOutputFile) { Clear-Content -Path $CVEOutputFile }

# Function to perform a web search using Google
function Search-CVE-Google {
    param ($ProgramName, $Version)
    $SearchQuery = "CVE $ProgramName $Version site:cve.mitre.org OR site:nvd.nist.gov"
    $SearchURL = "https://www.google.com/search?q=" + [System.Web.HttpUtility]::UrlEncode($SearchQuery)
    return $SearchURL
}

# Process each program
$CVEResults = @()
foreach ($Program in $Programs) {
    $ProgramName = $Program.Name
    $Version = $Program.Version
    if (-not $ProgramName) { continue }

    Log-Message "Checking CVEs for: $ProgramName $Version"
    Write-Host "`nChecking CVEs for: $ProgramName $Version" -ForegroundColor Cyan

    # Construct search URLs
    $MitreURL = "https://cve.mitre.org/cgi-bin/cvekey.cgi?keyword=" + [System.Web.HttpUtility]::UrlEncode($ProgramName)
    $NVDURL = "https://nvd.nist.gov/vuln/search/results?query=" + [System.Web.HttpUtility]::UrlEncode($ProgramName) + "&search_type=all"
    $GoogleURL = Search-CVE-Google -ProgramName $ProgramName -Version $Version

    # Save results
    $CVEEntry = @"
Program: $ProgramName
Version: $Version
MITRE: $MitreURL
NVD NIST: $NVDURL
Google Search: $GoogleURL
--------------------------------------------------
"@
    $CVEResults += @($MitreURL, $NVDURL, $GoogleURL)
    $CVEEntry | Out-File -FilePath $CVEOutputFile -Encoding utf8 -Append

    # Display results
    Write-Host "MITRE: $MitreURL"
    Write-Host "NVD NIST: $NVDURL"
    Write-Host "Google Search: $GoogleURL"
}

Log-Message "CVE search results saved to: $CVEOutputFile"
Write-Host "`nCVE search results saved to: $CVEOutputFile" -ForegroundColor Green

# Footer with Accents
Write-Host "==================================" -ForegroundColor Magenta
Log-Message "Completed CVE Finder"

# Prompt to open links in the browser
$Response = Read-Host "Do you want to open all search results in the browser? (Y/N)"
if ($Response -match "^[Yy]$") {
    foreach ($URL in $CVEResults) {
        Start-Process $URL
    }
}

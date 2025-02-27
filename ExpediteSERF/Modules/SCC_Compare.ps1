# PowerShell 7 script to compare findings from the last two SCC scans

# Define paths relative to the script's directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootPath = Split-Path -Parent $ScriptRoot

# Load configuration file
$configFile = Join-Path -Path $RootPath -ChildPath "config.ini"
$configContent = Get-Content $configFile | Where-Object { $_ -notmatch '^\s*;|^\s*$' }
$config = $configContent | ConvertFrom-StringData

# Define the path to SCC Sessions folder from config
$ResultsPath = $config.SESSION_FOLDER_PATH

# Define log file
$LogPath = Join-Path -Path $ScriptRoot -ChildPath "Logs\"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath | Out-Null }
$LogFile = Join-Path -Path $LogPath -ChildPath "SCC_Compare.log"

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

# Banner Output
Log-Message "Starting SCAP Compliance Scan Comparison"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Comparing " -NoNewline
Write-Host "Recent SCAP Scans" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Magenta

# Function to find the two latest session folders and get their XML reports
function Get-LatestReports {
    param ([string]$Path)
    
    # Get the two latest session folders
    $latestSessions = Get-ChildItem -Path $Path -Directory | Sort-Object Name -Descending | Select-Object -First 2
    
    $reportFiles = @()
    
    foreach ($session in $latestSessions) {
        # Look for the XML report
        $xmlReport = Get-ChildItem -Path "$($session.FullName)\Results\SCAP\XML" -Filter "*.xml" -ErrorAction SilentlyContinue
        if ($xmlReport) {
            $reportFiles += $xmlReport
        }
    }
    
    return $reportFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 2
}

# Function to find any "Non-Compliance" report dynamically
function Get-NonComplianceReport {
    param ([string]$SessionPath)

    # Look for any file with "Non-Compliance" in its name inside \Results\SCAP\
    $htmlReport = Get-ChildItem -Path "$SessionPath\Results\SCAP" -Filter "*Non-Compliance*.html" -ErrorAction SilentlyContinue | Select-Object -First 1

    return $htmlReport
}

# Function to extract scan details and compliance score
function Extract-ScanDetails {
    param ([string]$ReportPath)
    
    [xml]$xmlContent = Get-Content -Path $ReportPath -Raw
    
    # Register namespace for XPath queries
    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
    $namespaceManager.AddNamespace("xccdf", "http://checklists.nist.gov/xccdf/1.2")

    # Extract scan date and time from the filename
    if ($ReportPath -match "CYBER_SCC-5.7.1_(\d{4}-\d{2}-\d{2})_(\d{6})") {
        $scanDate = Get-Date $matches[1] -Format "MMMM dd, yyyy"
        $scanTime = [datetime]::ParseExact($matches[2], "HHmmss", $null).ToString("HH:mm:ss")
    } else {
        $scanDate = "Unknown"
        $scanTime = "Unknown"
    }

    # Extract compliance score using namespace
    $scoreNode = $xmlContent.SelectSingleNode("//xccdf:score", $namespaceManager)
    if ($scoreNode -and $scoreNode.InnerText -match "\d+(\.\d+)?") {
        $score = "{0:N2}%" -f [float]$scoreNode.InnerText
    } else {
        $score = "Unknown"
    }

    return @{ "Date" = "$scanDate - $scanTime"; "Score" = $score; "FilePath" = $ReportPath }
}

# Function to extract findings with V-ID and descriptions
function Extract-Findings {
    param ([string]$ReportPath)
    
    [xml]$xmlContent = Get-Content -Path $ReportPath -Raw

    # Register XML namespace
    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
    $namespaceManager.AddNamespace("xccdf", "http://checklists.nist.gov/xccdf/1.2")

    # Extract findings categorized by severity
    $findings = @{ "CAT I" = @(); "CAT II" = @(); "CAT III" = @() }
    
    foreach ($rule in $xmlContent.SelectNodes("//xccdf:rule-result", $namespaceManager)) {
        $severity = $rule.GetAttribute("severity")
        $ruleID = $rule.GetAttribute("idref")
        $result = $rule.SelectSingleNode("xccdf:result", $namespaceManager).InnerText

        # Extract description
        $ruleNode = $xmlContent.SelectSingleNode("//xccdf:Rule[@id='$ruleID']", $namespaceManager)
        $title = if ($ruleNode) { $ruleNode.SelectSingleNode("xccdf:title", $namespaceManager).InnerText } else { "No Description Found" }

        # Extract only the V-ID (e.g., "V-220721")
        if ($ruleID -match "SV-(\d+)r") {
            $vulnID = "V-$($matches[1])"
        } else {
            $vulnID = $ruleID
        }

        # Store failed findings
        if ($result -eq "fail") {
            $finding = "$($vulnID): $($title)"
            switch ($severity) {
                "high" { $findings["CAT I"] += $finding }
                "medium" { $findings["CAT II"] += $finding }
                "low" { $findings["CAT III"] += $finding }
            }
        }
    }
    
    return $findings
}

# Get the two latest reports from session folders
$latestReports = Get-LatestReports -Path $ResultsPath

if ($latestReports.Count -lt 2) {
    Log-Message "Not enough scan reports found for comparison." "ERROR"
    Write-Host "`n[ERROR] Not enough scan reports found for comparison." -ForegroundColor Red
    exit
}

# Extract scan details and findings from both reports
$scanDetails1 = Extract-ScanDetails -ReportPath $latestReports[0].FullName
$scanDetails2 = Extract-ScanDetails -ReportPath $latestReports[1].FullName
$extractedFindings1 = Extract-Findings -ReportPath $latestReports[0].FullName
$extractedFindings2 = Extract-Findings -ReportPath $latestReports[1].FullName

# Determine session paths for HTML report retrieval
$latestSessionPath = Split-Path -Parent $latestReports[0].FullName
$nonComplianceReport = Get-NonComplianceReport -SessionPath $latestSessionPath

# Print scan details
Log-Message "Latest Scan: $($scanDetails1['Date']) | Score: $($scanDetails1['Score'])"
Log-Message "Previous Scan: $($scanDetails2['Date']) | Score: $($scanDetails2['Score'])"
Write-Host "`n  Latest Scan:   $($scanDetails1['Date']) | Score: $($scanDetails1['Score'])" -ForegroundColor Cyan
Write-Host "  Previous Scan: $($scanDetails2['Date']) | Score: $($scanDetails2['Score'])"
Write-Host "----------------------------------" -ForegroundColor Magenta

# Compare findings
$orderedCategories = @("CAT I", "CAT II", "CAT III")
$differencesFound = $false

foreach ($category in $orderedCategories) {
    $newFindings = $extractedFindings1[$category] | Where-Object { $_ -notin $extractedFindings2[$category] }

    if ($newFindings.Count -gt 0) {
        $differencesFound = $true
        Log-Message "$category Findings"
        Write-Host "$category Findings" -ForegroundColor Cyan
        Write-Host "----------------------------------" -ForegroundColor Magenta
        Write-Host "New Findings:" -ForegroundColor Red
        $newFindings | Sort-Object | ForEach-Object { Write-Host "  - $_"; Log-Message "New Finding: $_" }

        $recurringFindings = $extractedFindings1[$category] | Where-Object { $_ -in $extractedFindings2[$category] }
        if ($recurringFindings.Count -gt 0) {
            Write-Host "Recurring Findings (Still Present):" -ForegroundColor Yellow
            $recurringFindings | Sort-Object | ForEach-Object { Write-Host "  - $_"; Log-Message "Recurring Finding: $_" }
        }

        $resolvedFindings = $extractedFindings2[$category] | Where-Object { $_ -notin $extractedFindings1[$category] }
        if ($resolvedFindings.Count -gt 0) {
            Write-Host "Resolved Findings (Previously Failed, Now Passed):" -ForegroundColor Green
            $resolvedFindings | Sort-Object | ForEach-Object { Write-Host "  - $_"; Log-Message "Resolved Finding: $_" }
        }
        Write-Host ""
    }
}

if (-not $differencesFound) {
    Log-Message "No new findings detected. Scans matched exactly."
    Write-Host "`n  [INFO] No new findings detected. " -NoNewline
    Write-Host "Scans matched exactly." -ForegroundColor Green
}

# Footer with Accents
Write-Host "==========================================" -ForegroundColor Magenta
Log-Message "Completed SCAP Compliance Scan Comparison"

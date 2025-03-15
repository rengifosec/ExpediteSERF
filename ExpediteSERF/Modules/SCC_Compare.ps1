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

# Function to log messages with different levels
Function Log-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "  $timestamp [$Level] $Message"
    $logEntry | Out-File -FilePath $LogFile -Append
}

# Banner Output
Log-Message "Starting SCAP Compliance Scan Comparison"
Write-Host ""
Write-Host "===========================================" -ForegroundColor Magenta
Write-Host "  Comparing " -NoNewline
Write-Host "Recent SCAP Scans" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Magenta

# Updated function to find the two latest session folders and get both their XML and HTML reports
function Get-LatestReports {
    param ([string]$Path)
    
    # Get the two latest session folders (assuming folder names sort as timestamps)
    $latestSessions = Get-ChildItem -Path $Path -Directory | Sort-Object Name -Descending | Select-Object -First 2
    
    $reportObjects = foreach ($session in $latestSessions) {
        # Build paths for the XML reports and the HTML Non-Compliance report
        $xmlPath = Join-Path -Path $session.FullName -ChildPath "Results\SCAP\XML"
        $htmlPath = Join-Path -Path $session.FullName -ChildPath "Results\SCAP"
        
        $xmlReport = Get-ChildItem -Path $xmlPath -Filter "*.xml" -ErrorAction SilentlyContinue | Select-Object -First 1
        $htmlReport = Get-ChildItem -Path $htmlPath -Filter "*Non-Compliance*.html" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($xmlReport) {
            [PSCustomObject]@{
                SessionFolder = $session.FullName
                XMLReport     = $xmlReport
                HTMLReport    = $htmlReport
            }
        }
    }
    
    return $reportObjects | Sort-Object { $_.XMLReport.LastWriteTime } -Descending | Select-Object -First 2
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

# Function to extract findings with V-ID and brief descriptions
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

        # Store failed findings with brief descriptions
        if ($result -eq "fail") {
            $briefTitle = ($title -split ' ')[0..9] -join ' '
            if (($title -split ' ').Count -gt 10) { $briefTitle += '...' }
            $finding = "$($vulnID): $($briefTitle)"
            switch ($severity) {
                "high" { $findings["CAT I"] += $finding }
                "medium" { $findings["CAT II"] += $finding }
                "low" { $findings["CAT III"] += $finding }
            }
        }
    }
    
    return $findings
}

# Get the two latest reports from session folders (with both XML and HTML reports)
$latestReports = Get-LatestReports -Path $ResultsPath

if ($latestReports.Count -lt 2) {
    Log-Message "Not enough scan reports found for comparison." "ERROR"
    Write-Host "`n[ERROR] Not enough scan reports found for comparison." -ForegroundColor Red
    exit
}

# Extract scan details and findings from both XML reports
$scanDetails1 = Extract-ScanDetails -ReportPath $latestReports[0].XMLReport.FullName
$scanDetails2 = Extract-ScanDetails -ReportPath $latestReports[1].XMLReport.FullName
$extractedFindings1 = Extract-Findings -ReportPath $latestReports[0].XMLReport.FullName
$extractedFindings2 = Extract-Findings -ReportPath $latestReports[1].XMLReport.FullName

# Print scan details
Log-Message "Latest Scan: $($scanDetails1['Date']) | Score: $($scanDetails1['Score'])"
Log-Message "Previous Scan: $($scanDetails2['Date']) | Score: $($scanDetails2['Score'])"
Write-Host "`n  Latest Scan:   $($scanDetails1['Date']) | Score: $($scanDetails1['Score'])" -ForegroundColor Cyan
Write-Host "  Previous Scan: $($scanDetails2['Date']) | Score: $($scanDetails2['Score'])"
Write-Host "-------------------------------------------" -ForegroundColor Magenta

# Compare findings
$orderedCategories = @("CAT I", "CAT II", "CAT III")
$differencesFound = $false

foreach ($category in $orderedCategories) {
    $newFindings = $extractedFindings1[$category] | Where-Object { $_ -notin $extractedFindings2[$category] }

    if ($newFindings.Count -gt 0) {
        $differencesFound = $true
        Log-Message "$category Findings"
        Write-Host "$category Findings" -ForegroundColor Cyan
        Write-Host "-------------------------------------------" -ForegroundColor Magenta
        Write-Host "New Findings:" -ForegroundColor Red
        $newFindings | Sort-Object | ForEach-Object { Write-Host "  - $_"; Log-Message "New Finding: $_" }

        $recurringFindings = $extractedFindings1[$category] | Where-Object { $_ -in $extractedFindings2[$category] }
        if ($recurringFindings.Count -gt 0) {
            Write-Host "`nRecurring Findings (Still Present):" -ForegroundColor Yellow
            $recurringFindings | Sort-Object | ForEach-Object { Write-Host "  - $_"; Log-Message "Recurring Finding: $_" }
        }

        $resolvedFindings = $extractedFindings2[$category] | Where-Object { $_ -notin $extractedFindings1[$category] }
        if ($resolvedFindings.Count -gt 0) {
            Write-Host "`nResolved Findings (Previously Failed, Now Passed):" -ForegroundColor Green
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
Write-Host "===========================================" -ForegroundColor Magenta
Log-Message "Completed SCAP Compliance Scan Comparison"

# Prompt to open the latest HTML Non-Compliance report for detailed review
# Prompt to open the latest HTML Non-Compliance report for detailed review
if ($differencesFound) {
    Write-Host "`nDo you want to open the latest HTML Non-Compliance report for detailed review? (Y/N)" -ForegroundColor Yellow
    $Response = Read-Host
    if ($Response -match "^[Yy]$") {
        if ($latestReports[0].HTMLReport) {

            # Build an array of new V-IDs from all categories
            $allNewVIDs = @()
            foreach ($category in $orderedCategories) {
                $catNewFindings = $extractedFindings1[$category] | Where-Object { $_ -notin $extractedFindings2[$category] }
                foreach ($finding in $catNewFindings) {
                    # Assume the finding format is "V-XXXXXX: description..."
                    if ($finding -match '^(V-\d+):') {
                        $vid = $matches[1]
                        $allNewVIDs += $vid
                    }
                }
            }
            $allNewVIDs = $allNewVIDs | Sort-Object -Unique

            # Read the HTML content
            $htmlFilePath = $latestReports[0].HTMLReport.FullName
            $htmlContent = Get-Content -Path $htmlFilePath -Raw
            
            # For each new V-ID, wrap any occurrence with a highlighting span tag.
            foreach ($vid in $allNewVIDs) {
                # This regex finds the V-ID and wraps it in a span with yellow background
                $pattern = "\b" + [regex]::Escape($vid) + "\b"
                $replacement = '<span style="color: #B026FF; font-style: italic">' + $vid + '</span>'
                $htmlContent = $htmlContent -replace $pattern, $replacement
            }
            
            # Save the modified HTML to a temporary file
            $tempHtmlFile = Join-Path -Path $env:TEMP -ChildPath "SCAP_NonCompliance_Highlighted.html"
            Set-Content -Path $tempHtmlFile -Value $htmlContent
            
            Write-Host "`nOpening HTML report for detailed review... New findings highlighted in " -NoNewline
            Write-Host "purple" -ForegroundColor Magenta

            Start-Process $tempHtmlFile
        } else {
            Write-Host "`nHTML Non-Compliance report not found for the latest session." -ForegroundColor Red
        }
    }
}


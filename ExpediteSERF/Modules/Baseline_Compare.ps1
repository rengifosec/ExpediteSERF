# Ensure script runs from its own directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path  

# Define new folder paths
$ResultsPath = Join-Path -Path $ScriptRoot -ChildPath "ScriptResults"
$BaselineFolder = Join-Path -Path $ResultsPath -ChildPath "baseline"
$ResultsFolder = Join-Path -Path $ResultsPath -ChildPath "results"
$NewProgramsFile = Join-Path -Path $ResultsPath -ChildPath "new_programs.txt"
$LogPath = Join-Path -Path $ScriptRoot -ChildPath "Logs\"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath }
$LogFile = Join-Path -Path $LogPath -ChildPath "Baseline_Compare.log"

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

# Display header
Log-Message "Starting SERF Baseline and Results Comparison"
Write-Host "`n===========================================" -ForegroundColor Magenta
Write-Host "  Comparing " -NoNewline
Write-Host "SERF Baseline & Results Files" -ForegroundColor Cyan
Write-Host "-------------------------------------------" -ForegroundColor Magenta

# Ensure required folders exist
if (!(Test-Path $BaselineFolder) -or !(Test-Path $ResultsFolder)) {
    Log-Message "Error: 'ScriptResults/baseline' and 'ScriptResults/results' folders must exist." "ERROR"
    exit 1
}

# Get all baseline files
$BaselineFiles = Get-ChildItem -Path $BaselineFolder -File

if ($BaselineFiles.Count -eq 0) {
    Log-Message "No files found in 'ScriptResults/baseline' to compare." "WARNING"
    exit 0
}

# Function to parse InstalledPrograms.txt into structured objects
function Parse-InstalledProgramsFile {
    param ($FilePath)
    
    if (!(Test-Path $FilePath)) {
        return @()  # Return empty array if file doesn't exist
    }

    $Programs = @()
    $CurrentProgram = @{}

    Get-Content -Path $FilePath | ForEach-Object {
        if ($_ -match "^\s*$") {
            if ($CurrentProgram.Count -gt 0) {
                $Programs += [PSCustomObject] $CurrentProgram
                $CurrentProgram = @{}
            }
        } elseif ($_ -match "^\s*([^:]+?)\s*:\s*(.*)$") {
            $CurrentProgram[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    if ($CurrentProgram.Count -gt 0) {
        $Programs += [PSCustomObject] $CurrentProgram
    }

    return $Programs
}

# Function to read, clean, and sort file content
function Get-CleanSortedFileContent {
    param ($FilePath)

    if (!(Test-Path $FilePath)) {
        return @()  # Return empty array if file doesn't exist
    }

    # Read file, trim whitespace, remove empty lines, and sort
    return Get-Content -Path $FilePath | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Sort-Object
}

# Track file processing state
$FilesFound = $false
$NewProgramsFound = $false  # Tracks if InstalledPrograms.txt had changes

# Process each file
foreach ($BaselineFile in $BaselineFiles) {
    $FilesFound = $true
    $ResultFile = Join-Path -Path $ResultsFolder -ChildPath $BaselineFile.Name

    if (!(Test-Path $ResultFile)) {
        Log-Message "File missing: $BaselineFile.Name" "WARNING"
        Write-Host ("  {0,-20} " -f $BaselineFile.Name) -NoNewline
        Write-Host "[MISSING]" -ForegroundColor Red
        continue
    }

    # Handle InstalledPrograms.txt separately (preserve program structure)
    if ($BaselineFile.Name -eq "InstalledPrograms.txt") {
        $BaselinePrograms = Parse-InstalledProgramsFile -FilePath $BaselineFile.FullName
        $ResultPrograms = Parse-InstalledProgramsFile -FilePath $ResultFile

        # Create lookup tables
        $BaselineLookup = @{}
        $BaselinePrograms | ForEach-Object { if ($_.IdentifyingNumber) { $BaselineLookup[$_.IdentifyingNumber] = $_ } }

        $ResultLookup = @{}
        $ResultPrograms | ForEach-Object { if ($_.IdentifyingNumber) { $ResultLookup[$_.IdentifyingNumber] = $_ } }

        # Find new programs
        $NewPrograms = $ResultLookup.Keys | Where-Object { -not $BaselineLookup.ContainsKey($_) } | ForEach-Object { $ResultLookup[$_] }

        if ($NewPrograms.Count -gt 0) {
            $NewProgramsFound = $true  
            Log-Message "InstalledPrograms.txt has new entries"
            Write-Host "`n  InstalledPrograms.txt has new entries:" -ForegroundColor Yellow
            
            "Newly Installed Programs:`n-------------------------------------------" | Out-File -FilePath $NewProgramsFile -Encoding utf8 -Append

            foreach ($Program in $NewPrograms) {
                Write-Host ""
                "" | Out-File -FilePath $NewProgramsFile -Encoding utf8 -Append  # Blank line for spacing
                
                foreach ($Property in $Program.PSObject.Properties) {
                    Write-Host " $($Property.Name) : $($Property.Value)"
                    "  + $($Property.Name) : $($Property.Value)" | Out-File -FilePath $NewProgramsFile -Encoding utf8 -Append
                }
            }
        } else {
            Write-Host ("  {0,-20} " -f "InstalledPrograms.txt") -NoNewline
            Write-Host "[MATCHED]" -ForegroundColor Green
        }
        continue
    }

    # Read, clean, and sort contents for all other files
    $BaselineContent = Get-CleanSortedFileContent -FilePath $BaselineFile.FullName
    $ResultContent = Get-CleanSortedFileContent -FilePath $ResultFile

    # Identify differences
    $MissingLines = $BaselineContent | Where-Object { $_ -notin $ResultContent }
    $AdditionalLines = $ResultContent | Where-Object { $_ -notin $BaselineContent }

    if ($MissingLines.Count -gt 0 -or $AdditionalLines.Count -gt 0) {
        Log-Message "Differences found in: $BaselineFile.Name"
        Write-Host "`n  Differences in: $($BaselineFile.Name)" -ForegroundColor Yellow
        
        # Display missing lines with red `-`
        $MissingLines | ForEach-Object { Write-Host "  -" -ForegroundColor Red -NoNewline; Write-Host " $_" }
        Write-Host ""
        # Display additional lines with green `+`
        $AdditionalLines | ForEach-Object { Write-Host "  +" -ForegroundColor Green -NoNewline; Write-Host " $_" }

        Write-Host ""  # Blank line for separation
    } else {
        Write-Host ("  {0,-20} " -f $BaselineFile.Name) -NoNewline
        Write-Host " [MATCHED]" -ForegroundColor Green
    }
}

# If InstalledPrograms.txt had new programs, print the output location
if ($NewProgramsFound) {
    Log-Message "InstalledPrograms.txt changes saved to: ScriptResults\new_programs.txt"
    Write-Host "`n  InstalledPrograms.txt changes saved to: ScriptResults\new_programs.txt" -ForegroundColor Magenta
}

# If no files were found, print message
if (-not $FilesFound) {
    Log-Message "No files were found in 'ScriptResults/baseline'." "WARNING"
    Write-Host "  No files were found in 'ScriptResults/baseline'." -ForegroundColor Yellow
}

# Footer with Accents
Write-Host "===========================================" -ForegroundColor Magenta

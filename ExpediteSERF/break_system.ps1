<#
    BreakSCAPCompliance.ps1
    -------------------------
    This script intentionally misconfigures a Windows 10 test system to trigger SCAP
    compliance failures. It applies changes across three categories:
    
      CAT I – High Severity:
        • Disables BitLocker on the C: drive.
        • Installs IIS (if the baseline requires IIS not to be present).
        • Sets Data Execution Prevention (DEP) to a less secure "OptIn" mode.
        • Disables Structured Exception Handling Overwrite Protection (SEHOP).
        • Enables reversible password encryption.

      CAT II – Medium Severity:
        • Sets all local user accounts to have passwords that never expire.
        • Enables SMB v1 protocol.
        • Disables account lockout (i.e. sets lockout threshold to 0).
        • Disables auditing for logon events (both success and failure).

      CAT III – Low Severity:
        • Disables Windows Firewall.
        • Disables Windows Defender SmartScreen.
        • Enables ICMP Redirects.
        • (Simulates) disabling password protected sharing.
        • Sets the Application Event Log size to a very low value (1024 KB).
    
    **WARNING:** These changes intentionally weaken security. Run this only in a test/lab
    environment.
#>

function Write-Message {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Color
}

# Confirm before proceeding
Write-Message "WARNING: This script will intentionally break system security settings for SCAP compliance testing." Red
Write-Message "Ensure you are running this on an isolated test system ONLY." Yellow
Write-Message "Press Y to continue or any other key to abort:" Yellow
$confirmation = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
if ($confirmation.Character -notin @("Y","y")) {
    Write-Message "Aborting script." Red
    exit
}

Write-Message "`nStarting CAT I (High Severity) changes..." Cyan

# --- CAT I – High Severity Changes ---
try {
    Write-Message "Disabling BitLocker on C: drive..."
    Start-Process -FilePath "manage-bde.exe" -ArgumentList "-off C:" -Wait -NoNewWindow
} catch {
    Write-Message "Error disabling BitLocker: $_" Red
}

try {
    Write-Message "Installing IIS Web Server Role..."
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -All -NoRestart
} catch {
    Write-Message "Error installing IIS: $_" Red
}

try {
    Write-Message "Setting DEP to 'OptIn' mode (less secure)..."
    bcdedit /set {current} nx OptIn | Out-Null
} catch {
    Write-Message "Error setting DEP: $_" Red
}

try {
    Write-Message "Disabling SEHOP..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "ProtectionMode" -Value 0 -ErrorAction Stop
} catch {
    Write-Message "Error disabling SEHOP: $_" Red
}

try {
    Write-Message "Enabling reversible password encryption..."
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "PasswordEncryption" -Value 1 -PropertyType DWORD -Force | Out-Null
} catch {
    Write-Message "Error enabling reversible password encryption: $_" Red
}

Write-Message "CAT I changes applied.`n" Green

Write-Message "Starting CAT II (Medium Severity) changes..." Cyan

# --- CAT II – Medium Severity Changes ---
try {
    Write-Message "Setting all local user accounts to have passwords that never expire..."
    Get-LocalUser | ForEach-Object { Set-LocalUser -Name $_.Name -PasswordNeverExpires $true }
} catch {
    Write-Message "Error setting password expiration: $_" Red
}

try {
    Write-Message "Enabling SMB v1 protocol..."
    Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
} catch {
    Write-Message "Error enabling SMB v1: $_" Red
}

try {
    Write-Message "Disabling account lockout threshold..."
    net accounts /lockoutthreshold:0 | Out-Null
} catch {
    Write-Message "Error disabling account lockout: $_" Red
}

try {
    Write-Message "Disabling auditing for Logon events (failure and success)..."
    auditpol /set /subcategory:"Logon" /failure:disable | Out-Null
    auditpol /set /subcategory:"Logon" /success:disable | Out-Null
} catch {
    Write-Message "Error disabling auditing: $_" Red
}

Write-Message "CAT II changes applied.`n" Green

Write-Message "Starting CAT III (Low Severity) changes..." Cyan

# --- CAT III – Low Severity Changes ---
try {
    Write-Message "Disabling Windows Firewall..."
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
} catch {
    Write-Message "Error disabling Windows Firewall: $_" Red
}

try {
    Write-Message "Disabling Windows Defender SmartScreen..."
    Set-MpPreference -EnableSmartScreen $false
} catch {
    Write-Message "Error disabling SmartScreen: $_" Red
}

try {
    Write-Message "Enabling ICMP Redirects..."
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "EnableICMPRedirects" -Value 1 -PropertyType DWORD -Force | Out-Null
} catch {
    Write-Message "Error enabling ICMP Redirects: $_" Red
}

try {
    Write-Message "Simulating disabling of password protected sharing..."
    # Note: There is no direct registry setting for password protected sharing.
    # This creates a dummy key for testing purposes.
    New-Item -Path "HKLM:\SOFTWARE\TestSecurity" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\TestSecurity" -Name "PasswordProtectedSharing" -Value 0 -PropertyType DWORD -Force | Out-Null
} catch {
    Write-Message "Error simulating password protected sharing disable: $_" Red
}

try {
    Write-Message "Setting Application Event Log size to 1024 KB..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application" -Name "MaxSize" -Value 1024 -ErrorAction Stop
} catch {
    Write-Message "Error setting event log size: $_" Red
}

Write-Message "CAT III changes applied.`n" Green

Write-Message "All test configuration changes have been applied." Yellow
Write-Message "Some changes may require a system reboot to take effect." Yellow

Pause

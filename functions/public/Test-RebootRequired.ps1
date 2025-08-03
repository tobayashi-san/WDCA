function Test-RebootRequired {
    <#
    .SYNOPSIS
        Checks if a system reboot is required

    .DESCRIPTION
        Checks various registry locations and file indicators for pending reboots

    .EXAMPLE
        Test-RebootRequired
    #>

    $rebootRequired = $false
    $reasons = @()

    try {
        # Check Windows Update reboot flag
        $wuReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
        if ($wuReboot) {
            $rebootRequired = $true
            $reasons += "Windows Update"
        }

        # Check Component Based Servicing reboot flag
        $cbsReboot = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
        if ($cbsReboot) {
            $rebootRequired = $true
            $reasons += "Component Based Servicing"
        }

        # Check pending file rename operations
        $pendingFileRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($pendingFileRename) {
            $rebootRequired = $true
            $reasons += "Pending File Rename Operations"
        }

        if ($rebootRequired) {
            Write-Logger "Reboot required. Reasons: $($reasons -join ', ')" "WARNING"
            return @{
                Required = $true
                Reasons = $reasons
            }
        }
        else {
            Write-Logger "No reboot required" "INFO"
            return @{
                Required = $false
                Reasons = @()
            }
        }
    }
    catch {
        Write-Logger "Error checking reboot requirement: $($_.Exception.Message)" "ERROR"
        return @{
            Required = $false
            Reasons = @()
        }
    }
}
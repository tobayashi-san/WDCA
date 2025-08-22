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
        Write-Logger "Checking for pending reboot requirements..." "INFO"

        # Check Windows Update reboot flag
        try {
            $wuReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
            if ($wuReboot) {
                $rebootRequired = $true
                $reasons += "Windows Update"
                Write-Logger "Windows Update reboot flag detected" "INFO"
            }
        } catch {
            Write-Logger "Could not check Windows Update reboot flag: $($_.Exception.Message)" "DEBUG"
        }

        # Check Component Based Servicing reboot flag
        try {
            $cbsReboot = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
            if ($cbsReboot) {
                $rebootRequired = $true
                $reasons += "Component Based Servicing"
                Write-Logger "CBS reboot pending detected" "INFO"
            }
        } catch {
            Write-Logger "Could not check CBS reboot flag: $($_.Exception.Message)" "DEBUG"
        }

        # Check pending file rename operations
        try {
            $pendingFileRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
            if ($pendingFileRename -and $pendingFileRename.PendingFileRenameOperations) {
                $rebootRequired = $true
                $reasons += "Pending File Rename Operations"
                Write-Logger "Pending file rename operations detected" "INFO"
            }
        } catch {
            Write-Logger "Could not check pending file rename operations: $($_.Exception.Message)" "DEBUG"
        }

        # Check for Configuration Manager client reboot
        try {
            $ccmReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData" -ErrorAction SilentlyContinue
            if ($ccmReboot) {
                $rebootRequired = $true
                $reasons += "Configuration Manager"
                Write-Logger "Configuration Manager reboot pending detected" "INFO"
            }
        } catch {
            Write-Logger "Could not check Configuration Manager reboot flag: $($_.Exception.Message)" "DEBUG"
        }

        # Check ServerManager reboot flag (Windows Server)
        try {
            $serverManagerReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts" -ErrorAction SilentlyContinue
            if ($serverManagerReboot) {
                $rebootRequired = $true
                $reasons += "Server Manager"
                Write-Logger "Server Manager reboot pending detected" "INFO"
            }
        } catch {
            Write-Logger "Could not check Server Manager reboot flag: $($_.Exception.Message)" "DEBUG"
        }

        # Check for Domain Join reboot
        try {
            $domainJoinReboot = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon" -Name "JoinDomain" -ErrorAction SilentlyContinue
            if ($domainJoinReboot) {
                $rebootRequired = $true
                $reasons += "Domain Join"
                Write-Logger "Domain Join reboot pending detected" "INFO"
            }
        } catch {
            Write-Logger "Could not check Domain Join reboot flag: $($_.Exception.Message)" "DEBUG"
        }

        # Check for DSC reboot
        try {
            $dscReboot = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*DSCReboot*" -ErrorAction SilentlyContinue
            if ($dscReboot) {
                $rebootRequired = $true
                $reasons += "PowerShell DSC"
                Write-Logger "PowerShell DSC reboot pending detected" "INFO"
            }
        } catch {
            Write-Logger "Could not check DSC reboot flag: $($_.Exception.Message)" "DEBUG"
        }

        if ($rebootRequired) {
            Write-Logger "Reboot required. Reasons: $($reasons -join ', ')" "WARNING"
            return @{
                Required = $true
                Reasons = $reasons
                Count = $reasons.Count
                Summary = "System reboot required ($($reasons.Count) reason$(if($reasons.Count -gt 1){'s'}))"
            }
        }
        else {
            Write-Logger "No reboot required" "INFO"
            return @{
                Required = $false
                Reasons = @()
                Count = 0
                Summary = "No pending reboot requirements detected"
            }
        }
    }
    catch {
        Write-Logger "Error checking reboot requirement: $($_.Exception.Message)" "ERROR"
        return @{
            Required = $false
            Reasons = @("Error during check")
            Count = 0
            Summary = "Error checking reboot requirements: $($_.Exception.Message)"
        }
    }
}

function Invoke-WPFRebootManagement {
    <#
    .SYNOPSIS
        Handles reboot management actions

    .PARAMETER Action
        The reboot action to perform

    .EXAMPLE
        Invoke-WPFRebootManagement -Action "CheckPending"
        Invoke-WPFRebootManagement -Action "ScheduleReboot"
        Invoke-WPFRebootManagement -Action "CancelReboot"
    #>

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("CheckPending", "ScheduleReboot", "CancelReboot")]
        [string]$Action
    )

    Write-Logger "Starting reboot management action: $Action" "INFO"

    switch ($Action) {
        "CheckPending" {
            Invoke-RebootCheck
        }
        "ScheduleReboot" {
            Invoke-ScheduleReboot
        }
        "CancelReboot" {
            Invoke-CancelReboot
        }
    }
}

function Invoke-RebootCheck {
    <#
    .SYNOPSIS
        Checks for pending reboot requirements and displays results
    #>

    Write-Logger "Checking for pending reboot requirements" "INFO"

    try {
        $rebootStatus = Test-RebootRequired

        $title = if ($rebootStatus.Required) {
            "WDCA - Reboot Required"
        } else {
            "WDCA - No Reboot Required"
        }

        $icon = if ($rebootStatus.Required) {
            [System.Windows.MessageBoxImage]::Warning
        } else {
            [System.Windows.MessageBoxImage]::Information
        }

        if ($rebootStatus.Required -and $rebootStatus.Reasons.Count -gt 0) {
            $message = "System reboot required.`n`nDetected reasons:`n"
            foreach ($reason in $rebootStatus.Reasons) {
                $message += "• $reason`n"
            }
            $message += "`nRecommendation: Plan a maintenance window to restart the system."
        } else {
            $message = "No reboot required.`n`nThe system is operating normally without pending restart requirements."
        }

        [System.Windows.MessageBox]::Show(
            $message,
            $title,
            [System.Windows.MessageBoxButton]::OK,
            $icon
        )

        Write-Logger "Reboot check completed. Required: $($rebootStatus.Required)" "INFO"
    }
    catch {
        Write-Logger "Error checking reboot status: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Error checking reboot status: $($_.Exception.Message)",
            "WDCA - Reboot Check Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Invoke-ScheduleReboot {
    <#
    .SYNOPSIS
        Schedules a system restart
    #>

    Write-Logger "Initiating scheduled reboot configuration" "INFO"

    try {
        # Show options dialog for reboot scheduling
        $scheduleMessage = @"
Schedule System Restart

Choose when to restart the system:

• Immediate Restart (5 seconds)
• Restart in 5 minutes
• Restart in 15 minutes
• Restart in 30 minutes
• Restart in 1 hour
• Cancel

Select scheduling option:
"@

        # Create custom dialog for scheduling options
        Add-Type -AssemblyName Microsoft.VisualBasic
        $scheduleChoice = [Microsoft.VisualBasic.Interaction]::InputBox(
            "Enter minutes to wait before restart (0 for immediate, 1-1440 for delayed):",
            "WDCA - Schedule Restart",
            "5"
        )

        if ([string]::IsNullOrEmpty($scheduleChoice)) {
            Write-Logger "Restart scheduling cancelled by user" "INFO"
            return
        }

        # Validate input
        $delayMinutes = 0
        if (-not [int]::TryParse($scheduleChoice, [ref]$delayMinutes)) {
            [System.Windows.MessageBox]::Show(
                "Invalid input. Please enter a number between 0 and 1440.",
                "WDCA - Invalid Input",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        if ($delayMinutes -lt 0 -or $delayMinutes -gt 1440) {
            [System.Windows.MessageBox]::Show(
                "Please enter a number between 0 and 1440 minutes (24 hours).",
                "WDCA - Invalid Range",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        # Convert minutes to seconds for shutdown command
        $delaySeconds = $delayMinutes * 60

        # Confirmation dialog
        $timeText = if ($delayMinutes -eq 0) {
            "immediately (5 seconds)"
        } elseif ($delayMinutes -eq 1) {
            "in 1 minute"
        } else {
            "in $delayMinutes minutes"
        }

        $confirmResult = [System.Windows.MessageBox]::Show(
            "Schedule system restart $timeText`?`n`nThis will close all applications and restart the computer.",
            "WDCA - Confirm Restart",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-Logger "Restart scheduling cancelled by user" "INFO"
            return
        }

        # Schedule the restart
        if ($delayMinutes -eq 0) {
            # Immediate restart (5 second delay for safety)
            shutdown.exe /r /t 5 /c "Restart scheduled by WDCA - System will restart in 5 seconds"
            $statusMessage = "System restart scheduled immediately (5 seconds)"
        } else {
            # Delayed restart
            shutdown.exe /r /t $delaySeconds /c "Restart scheduled by WDCA - System will restart in $delayMinutes minutes"
            $statusMessage = "System restart scheduled in $delayMinutes minutes"
        }

        Write-Logger "System restart scheduled: $statusMessage" "INFO"

        [System.Windows.MessageBox]::Show(
            "$statusMessage`n`nUse 'Cancel Scheduled Restart' to abort if needed.",
            "WDCA - Restart Scheduled",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
    }
    catch {
        Write-Logger "Error scheduling restart: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Error scheduling restart: $($_.Exception.Message)",
            "WDCA - Schedule Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Invoke-CancelReboot {
    <#
    .SYNOPSIS
        Cancels a scheduled system restart
    #>

    Write-Logger "Attempting to cancel scheduled restart" "INFO"

    try {
        # Cancel any scheduled shutdown
        $result = shutdown.exe /a

        Write-Logger "Scheduled restart cancellation attempted" "INFO"

        [System.Windows.MessageBox]::Show(
            "Attempted to cancel scheduled restart.`n`nIf no restart was scheduled, this action has no effect.",
            "WDCA - Cancel Restart",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
    }
    catch {
        Write-Logger "Error cancelling restart: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Error cancelling restart: $($_.Exception.Message)",
            "WDCA - Cancel Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Get-RebootStatus {
    <#
    .SYNOPSIS
        Gets detailed reboot status information for display
    #>

    try {
        $rebootInfo = Test-RebootRequired

        return @{
            Status = if ($rebootInfo.Required) { "Required" } else { "Not Required" }
            Reasons = $rebootInfo.Reasons
            Count = $rebootInfo.Count
            Summary = $rebootInfo.Summary
            LastChecked = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    catch {
        Write-Logger "Error getting reboot status: $($_.Exception.Message)" "ERROR"
        return @{
            Status = "Error"
            Reasons = @("Error during status check")
            Count = 0
            Summary = "Error checking reboot status"
            LastChecked = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

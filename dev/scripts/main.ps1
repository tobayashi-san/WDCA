# Fixed scripts/main.ps1 with Form-Validation and Error Handling

try {
    Write-Logger "Starting WDCA UI initialization..." "INFO"

    # Check if inputXML exists
    if (-not $inputXML) {
        throw "inputXML variable is not defined or empty"
    }

    # XAML parsing with improved error handling
    try {
        [xml]$XAML = $inputXML
        Write-Logger "XAML parsed successfully" "INFO"

        $reader = (New-Object System.Xml.XmlNodeReader $XAML)
        $global:sync.Form = [Windows.Markup.XamlReader]::Load($reader)

        # Critical Form validation
        if (-not $global:sync.Form) {
            throw "Failed to load XAML - Form is null"
        }

        # Additional Form validation
        if (-not $global:sync.Form.GetType().Name.Contains("Window")) {
            throw "Loaded object is not a Window type"
        }

        Write-Logger "XAML loaded successfully - Form created and validated" "INFO"
    }
    catch [System.Windows.Markup.XamlParseException] {
        Write-Logger "XAML Parse Error: $($_.Exception.Message)" "ERROR"
        Write-Logger "Line: $($_.Exception.LineNumber), Position: $($_.Exception.LinePosition)" "ERROR"
        throw "XAML parsing failed: $($_.Exception.Message)"
    }
    catch {
        Write-Logger "Error loading XAML: $($_.Exception.Message)" "ERROR"
        throw "XAML loading failed: $($_.Exception.Message)"
    }

    # Safely initialize components with error checking
    try {
        Write-Logger "Initializing XAML variables..." "INFO"
        Initialize-WDCAVariables
    }
    catch {
        Write-Logger "Error initializing XAML variables: $($_.Exception.Message)" "ERROR"
    }

    try {
        Write-Logger "Initializing theme manager..." "INFO"
        Initialize-ThemeManager
    }
    catch {
        Write-Logger "Error initializing theme manager: $($_.Exception.Message)" "ERROR"
    }

    try {
        Write-Logger "Applying system theme..." "INFO"
        $systemTheme = Get-SystemThemePreference
        Set-WDCATheme -ThemeName $systemTheme
    }
    catch {
        Write-Logger "Error applying theme: $($_.Exception.Message)" "ERROR"
    }

    try {
        Write-Logger "Initializing window controls..." "INFO"
        Initialize-WindowControls
    }
    catch {
        Write-Logger "Error initializing window controls: $($_.Exception.Message)" "ERROR"
    }

    try {
        Write-Logger "Initializing applications..." "INFO"
        Initialize-WDCAApplications
    }
    catch {
        Write-Logger "Error initializing applications: $($_.Exception.Message)" "ERROR"
    }

    Write-Logger "WDCA UI successfully initialized" "INFO"

    # Initialize navigation
    $currentTab = "Applications"

    function Show-Content {
        param([string]$TabName)

        try {
            # Hide all content panels
            @("ApplicationsContent", "SystemSetupContent", "TroubleshootingContent", "UpdatesContent", "CloningContent", "SettingsContent", "AboutContent") | ForEach-Object {
                if ($sync[$_]) {
                    $sync[$_].Visibility = "Collapsed"
                }
            }

            # Show selected content
            $contentName = "${TabName}Content"
            if ($sync[$contentName]) {
                $sync[$contentName].Visibility = "Visible"
            }

            # Update navigation button states
            @("NavApplications", "NavSystemSetup", "NavTroubleshooting", "NavUpdates", "NavCloning", "NavSettings", "NavAbout") | ForEach-Object {
                if ($sync[$_]) {
                    $sync[$_].Tag = ""
                }
            }

            $navButtonName = "Nav$TabName"
            if ($sync[$navButtonName]) {
                $sync[$navButtonName].Tag = "Selected"
            }

            $script:currentTab = $TabName
            Set-WDCAStatus "Switched to $TabName"
        }
        catch {
            Write-Logger "Error switching to tab ${TabName}: $($_.Exception.Message)" "ERROR"
        }
    }

    # Navigation event handlers with error handling
    if ($sync.NavApplications) {
        $sync.NavApplications.Add_Click({
                try {
                    if ((Get-ActiveAsyncOperations).Count -eq 0) {
                        Show-Content "Applications"
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Please wait for current operation to complete.", "WDCA - Operation in Progress", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                }
                catch {
                    Write-Logger "Error in Applications navigation: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.NavSystemSetup) {
        $sync.NavSystemSetup.Add_Click({
                try {
                    if ((Get-ActiveAsyncOperations).Count -eq 0) {
                        Show-Content "SystemSetup"
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Please wait for current operation to complete.", "WDCA - Operation in Progress", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                }
                catch {
                    Write-Logger "Error in SystemSetup navigation: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.NavTroubleshooting) {
        $sync.NavTroubleshooting.Add_Click({
                try {
                    if ((Get-ActiveAsyncOperations).Count -eq 0) {
                        Show-Content "Troubleshooting"
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Please wait for current operation to complete.", "WDCA - Operation in Progress", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                }
                catch {
                    Write-Logger "Error in Troubleshooting navigation: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.NavUpdates) {
        $sync.NavUpdates.Add_Click({
                try {
                    if ((Get-ActiveAsyncOperations).Count -eq 0) {
                        Show-Content "Updates"
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Please wait for current operation to complete.", "WDCA - Operation in Progress", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                }
                catch {
                    Write-Logger "Error in Updates navigation: $($_.Exception.Message)" "ERROR"
                }
            })
    }

if ($sync.NavCloning) {
        $sync.NavCloning.Add_Click({
                try {
                    if ((Get-ActiveAsyncOperations).Count -eq 0) {
                        Show-Content "Cloning"
                    }
                    else {
                        [System.Windows.MessageBox]::Show("Please wait for current operation to complete.", "WDCA - Operation in Progress", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                }
                catch {
                    Write-Logger "Error in Cloning navigation: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.NavSettings) {
        $sync.NavSettings.Add_Click({
                try {
                    Show-Content "Settings"
                }
                catch {
                    Write-Logger "Error in Settings navigation: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.NavAbout) {
        $sync.NavAbout.Add_Click({
                try {
                    Show-Content "About"
                }
                catch {
                    Write-Logger "Error in About navigation: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    # Application event handlers
    if ($sync.WPFInstallSelectedApps) {
        $sync.WPFInstallSelectedApps.Add_Click({
                try {
                    Invoke-WPFApplicationsAsync
                }
                catch {
                    Write-Logger "Error in Install Selected Apps: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFSelectAllApps) {
        $sync.WPFSelectAllApps.Add_Click({
                try {
                    if ($sync.configs.applications) {
                        $sync.configs.applications.PSObject.Properties | ForEach-Object {
                            $checkboxName = $_.Name
                            if ($sync[$checkboxName]) {
                                $sync[$checkboxName].IsChecked = $true
                            }
                        }
                    }
                    Set-WDCAStatus "Selected all applications"
                }
                catch {
                    Write-Logger "Error in Select All Apps: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFDeselectAllApps) {
        $sync.WPFDeselectAllApps.Add_Click({
                try {
                    if ($sync.configs.applications) {
                        $sync.configs.applications.PSObject.Properties | ForEach-Object {
                            $checkboxName = $_.Name
                            if ($sync[$checkboxName]) {
                                $sync[$checkboxName].IsChecked = $false
                            }
                        }
                    }
                    Set-WDCAStatus "Deselected all applications"
                }
                catch {
                    Write-Logger "Error in Deselect All Apps: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    # System Setup event handlers
    if ($sync.WPFConfigureNetwork) {
        $sync.WPFConfigureNetwork.Add_Click({
                try {
                    Invoke-WPFSystemSetup -Action "Network"
                }
                catch {
                    Write-Logger "Error in Configure Network: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFEnableRDP) {
        $sync.WPFEnableRDP.Add_Click({
                try {
                    Invoke-WPFSystemSetup -Action "RDP"
                }
                catch {
                    Write-Logger "Error in Enable RDP: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    # Troubleshooting event handlers
    if ($sync.WPFRunDiagnostics) {
        $sync.WPFRunDiagnostics.Add_Click({
                try {
                    Invoke-SystemDiagnosticsAsync
                }
                catch {
                    Write-Logger "Error in Run Diagnostics: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFRunDISM) {
        $sync.WPFRunDISM.Add_Click({
                try {
                    Invoke-WPFTroubleshooting -Action "DISM"
                }
                catch {
                    Write-Logger "Error in Run DISM: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFRunSFC) {
        $sync.WPFRunSFC.Add_Click({
                try {
                    Invoke-WPFTroubleshooting -Action "SFC"
                }
                catch {
                    Write-Logger "Error in Run SFC: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFRunCHKDSK) {
        $sync.WPFRunCHKDSK.Add_Click({
                try {
                    Invoke-WPFTroubleshooting -Action "CHKDSK"
                }
                catch {
                    Write-Logger "Error in Run CHKDSK: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFListAppUpdate) {
        $sync.WPFListAppUpdate.Add_Click({
                try {
                    Invoke-WPFListAppUpdates
                }
                catch {
                    Write-Logger "Error in Update Apps: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFUpdateApps) {
        $sync.WPFUpdateApps.Add_Click({
                try {
                    Invoke-WPFUpdateApps
                }
                catch {
                    Write-Logger "Error in Upgrade Apps: $($_.Exception.Message)" "ERROR"
                }
            })
    }

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
            }
            catch {
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
            }
            catch {
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
            }
            catch {
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
            }
            catch {
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
            }
            catch {
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
            }
            catch {
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
            }
            catch {
                Write-Logger "Could not check DSC reboot flag: $($_.Exception.Message)" "DEBUG"
            }

            if ($rebootRequired) {
                Write-Logger "Reboot required. Reasons: $($reasons -join ', ')" "WARNING"
                return @{
                    Required = $true
                    Reasons  = $reasons
                    Count    = $reasons.Count
                    Summary  = "System reboot required due to: $($reasons -join ', ')"
                }
            }
            else {
                Write-Logger "No reboot required" "INFO"
                return @{
                    Required = $false
                    Reasons  = @()
                    Count    = 0
                    Summary  = "No pending reboot requirements detected"
                }
            }
        }
        catch {
            Write-Logger "Error checking reboot requirement: $($_.Exception.Message)" "ERROR"
            return @{
                Required = $false
                Reasons  = @("Error during check")
                Count    = 0
                Summary  = "Error checking reboot requirements: $($_.Exception.Message)"
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
            }
            else {
                "WDCA - No Reboot Required"
            }

            $icon = if ($rebootStatus.Required) {
                [System.Windows.MessageBoxImage]::Warning
            }
            else {
                [System.Windows.MessageBoxImage]::Information
            }

            $message = $rebootStatus.Summary

            if ($rebootStatus.Required -and $rebootStatus.Reasons.Count -gt 0) {
                $message += "`n`nDetailed reasons:`n"
                $rebootStatus.Reasons | ForEach-Object {
                    $message += "â€¢ $_`n"
                }
                $message += "`nRecommendation: Plan a maintenance window to restart the system."
            }
            else {
                $message += "`n`nThe system is operating normally without pending restart requirements."
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

â€¢ Immediate Restart (5 seconds)
â€¢ Restart in 5 minutes
â€¢ Restart in 15 minutes
â€¢ Restart in 30 minutes
â€¢ Restart in 1 hour
â€¢ Cancel

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
            }
            elseif ($delayMinutes -eq 1) {
                "in 1 minute"
            }
            else {
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
            }
            else {
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

    # Event Handlers fÃ¼r Reboot Management (ErgÃ¤nzung fÃ¼r main.ps1)
    # Diese Event-Handler sollten zu den bestehenden Event-Handlers in main.ps1 hinzugefÃ¼gt werden

    # Reboot Management Event Handlers
    if ($sync.WPFCheckPendingReboot) {
        $sync.WPFCheckPendingReboot.Add_Click({
                try {
                    Invoke-WPFRebootManagement -Action "CheckPending"
                }
                catch {
                    Write-Logger "Error in Check Pending Reboot: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFScheduleReboot) {
        $sync.WPFScheduleReboot.Add_Click({
                try {
                    Invoke-WPFRebootManagement -Action "ScheduleReboot"
                }
                catch {
                    Write-Logger "Error in Schedule Reboot: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFCancelReboot) {
        $sync.WPFCancelReboot.Add_Click({
                try {
                    Invoke-WPFRebootManagement -Action "CancelReboot"
                }
                catch {
                    Write-Logger "Error in Cancel Reboot: $($_.Exception.Message)" "ERROR"
                }
            })
    }
# Cloning event handlers
if ($sync.WPFRunCleanup) {
    $sync.WPFRunCleanup.Add_Click({
        try {
            Invoke-PreCloneCleanup
        }
        catch {
            Write-Logger "Error in Run Cleanup: $($_.Exception.Message)" "ERROR"
            [System.Windows.MessageBox]::Show(
                "Error starting cleanup: $($_.Exception.Message)",
                "WDCA - Cleanup Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    })
}

# About page event handlers
    if ($sync.ViewWiki) {
        $sync.ViewWiki.Add_Click({
                try {
                    Write-Logger "Opening WDCA documentation" "INFO"
                    Start-Process "https://github.com/Tobayashi-san/WDCA" -ErrorAction Stop
                }
                catch {
                    Write-Logger "Error opening documentation: $($_.Exception.Message)" "ERROR"
                    [System.Windows.MessageBox]::Show(
                        "Could not open documentation. Please visit:`nhttps://github.com/Tobayashi-san/WDCA/wiki",
                        "WDCA - Documentation",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                }
            })
    }

    if ($sync.ReportIssue) {
        $sync.ReportIssue.Add_Click({
                try {
                    Write-Logger "Opening issue reporting page" "INFO"
                    Start-Process "https://github.com/Tobayashi-san/WDCA/issues/new" -ErrorAction Stop
                }
                catch {
                    Write-Logger "Error opening issue page: $($_.Exception.Message)" "ERROR"
                    [System.Windows.MessageBox]::Show(
                        "Could not open issue reporting page. Please visit:`nhttps://github.com/Tobayashi-san/WDCA/issues/new",
                        "WDCA - Report Issue",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                }
            })
    }

    # Update status and version display
    if ($sync.WPFVersionText) {
        $sync.WPFVersionText.Text = "25.01.01"
    }

    if ($sync.PowerShellVersion) {
        $sync.PowerShellVersion.Text = $PSVersionTable.PSVersion.ToString()
    }

    if ($sync.AdminStatus) {
        $isAdmin = Test-IsAdmin
        $sync.AdminStatus.Text = if ($isAdmin) { "Yes" } else { "No" }
        $sync.AdminStatus.Foreground = if ($isAdmin) { "#FF107C10" } else { "#FFD13438" }
    }

    if ($sync.WinGetStatus) {
        $hasWinGet = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        $sync.WinGetStatus.Text = if ($hasWinGet) { "Yes" } else { "No" }
        $sync.WinGetStatus.Foreground = if ($hasWinGet) { "#FF107C10" } else { "#FFD13438" }
    }

    if ($sync.LogFilePath) {
        $sync.LogFilePath.Text = $sync.logFile
    }

    if ($sync.SystemComputerName) {
        $sync.SystemComputerName.Text = $env:COMPUTERNAME
    }

    Set-WDCAStatus "WDCA initialized and ready"

    # Initialize async operations support
    Initialize-RunspacePool
    $global:ActiveOperations = @{}
    $global:UIStateStack = @()

    # Setup cleanup on window close
    $sync.Form.Add_Closing({
            try {
                Write-Logger "Application closing - cleaning up async operations" "INFO"
                Stop-AllAsyncOperations
                Close-RunspacePool
            }
            catch {
                Write-Logger "Error during window close cleanup: $($_.Exception.Message)" "ERROR"
            }
        })

    # FIXED: Safer exception handler setup
    try {
        $sync.Form.Add_SourceInitialized({
                try {
                    # Check if Dispatcher exists before adding handler
                    if ($sync.Form.Dispatcher -and $sync.Form.Dispatcher.UnhandledException) {
                        $sync.Form.Dispatcher.UnhandledException.Add({
                                param($sender, $e)
                                Write-Logger "Unhandled exception: $($e.Exception.Message)" "ERROR"
                                Stop-AllAsyncOperations
                                $e.Handled = $true
                            })
                    }
                }
                catch {
                    Write-Logger "Could not set up exception handler: $($_.Exception.Message)" "WARNING"
                }
            })
    }
    catch {
        Write-Logger "Error setting up source initialized handler: $($_.Exception.Message)" "WARNING"
    }

    # Set initial content
    Show-Content "Applications"

    # Final validation before showing dialog
    if ($sync.Form -eq $null) {
        throw "Form is null - cannot display window"
    }

    Write-Logger "Showing main window..." "INFO"

    # Show the window with error handling
    try {
        $sync.Form.ShowDialog() | Out-Null
    }
    catch [System.InvalidOperationException] {
        Write-Logger "InvalidOperationException during ShowDialog: $($_.Exception.Message)" "ERROR"
        # Try alternative approach
        try {
            $sync.Form.Show()
            # Keep application alive
            [System.Windows.Threading.Dispatcher]::Run()
        }
        catch {
            Write-Logger "Alternative show method also failed: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
    catch {
        Write-Logger "Unexpected error during ShowDialog: $($_.Exception.Message)" "ERROR"
        throw
    }
}
catch {
    Write-Logger "Critical error in main execution: $($_.Exception.Message)" "ERROR"
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red

    # Try more detailed error analysis
    if ($_.Exception.InnerException) {
        Write-Host "Inner exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }

    # Form-specific diagnosis
    if ($global:sync.Form) {
        Write-Host "Form status: Exists" -ForegroundColor Yellow
        try {
            Write-Host "Form type: $($global:sync.Form.GetType().FullName)" -ForegroundColor Yellow
            Write-Host "Form IsLoaded: $($global:sync.Form.IsLoaded)" -ForegroundColor Yellow
        }
        catch {
            Write-Host "Cannot get form details: $($_.Exception.Message)" -ForegroundColor Red
        }

        try {
            $sync.Form.Close()
        }
        catch {
            Write-Logger "Error closing form: $($_.Exception.Message)" "ERROR"
        }
    }
    else {
        Write-Host "Form status: NULL" -ForegroundColor Red
    }

    Read-Host "Press Enter to exit"
}
finally {
    # Cleanup async operations
    try {
        Write-Logger "Starting final cleanup..." "INFO"
        Stop-AllAsyncOperations
        Close-RunspacePool
        Write-Logger "Async operations cleaned up" "INFO"
    }
    catch {
        Write-Logger "Error during async cleanup: $($_.Exception.Message)" "ERROR"
    }

    # Clear sync hashtable
    if ($sync) {
        try {
            $sync.Clear()
            Write-Logger "Sync hashtable cleared" "INFO"
        }
        catch {
            Write-Logger "Error clearing sync hashtable: $($_.Exception.Message)" "ERROR"
        }
    }

    Write-Logger "WDCA execution completed" "INFO"
}

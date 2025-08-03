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

    if ($sync.WPFPrepareDC) {
        $sync.WPFPrepareDC.Add_Click({
                try {
                    $targetVersion = $sync.WPFDCTargetVersion.SelectedItem.Content
                    Invoke-DomainControllerUpgradePrep -TargetWindowsVersion $targetVersion
                }
                catch {
                    Write-Logger "Error in DC Prep: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFAnalyzeFSMO) {
        $sync.WPFAnalyzeFSMO.Add_Click({
                try {
                    Invoke-FSMORoleAnalysis
                }
                catch {
                    Write-Logger "Error in FSMO Analysis: $($_.Exception.Message)" "ERROR"
                }
            })
    }

    if ($sync.WPFCheckReplication) {
        $sync.WPFCheckReplication.Add_Click({
                try {
                    Invoke-ADReplicationCheck
                }
                catch {
                    Write-Logger "Error in Replication Check: $($_.Exception.Message)" "ERROR"
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
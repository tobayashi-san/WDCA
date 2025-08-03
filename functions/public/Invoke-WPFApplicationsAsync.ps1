function Invoke-WPFApplicationsAsync {
    <#
    .SYNOPSIS
        WinGet Installation in neuem Terminal-Fenster
    #>

    Write-Logger "Starting WinGet installation in new terminal" "INFO"

    # Ausgewählte Apps sammeln
    $selectedApps = @()
    if ($sync.configs.applications) {
        foreach ($app in $sync.configs.applications.PSObject.Properties) {
            $checkboxName = $app.Name
            if ($sync[$checkboxName] -and $sync[$checkboxName].IsChecked -eq $true) {
                $selectedApps += @{
                    Name        = $checkboxName
                    DisplayName = $app.Value.content
                    WingetId    = $app.Value.winget
                    Description = $app.Value.description
                }
            }
        }
    }

    if ($selectedApps.Count -eq 0) {
        Write-Logger "No applications selected for installation" "WARNING"
        [System.Windows.MessageBox]::Show("Please select at least one application to install.", "WDCA - No Selection", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }

    # Bestätigung
    $confirmResult = [System.Windows.MessageBox]::Show(
        "Install $($selectedApps.Count) selected applications?`n`nInstallation will start in a new terminal window.",
        "WDCA - Confirm Installation",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Application installation cancelled by user" "INFO"
        return
    }

    # WinGet test
    try {
        Write-Logger "Testing WinGet availability..." "INFO"
        $wingetTest = Start-Process -FilePath "winget" -ArgumentList "--version" -Wait -PassThru -WindowStyle Hidden
        if ($wingetTest.ExitCode -ne 0) {
            throw "WinGet not working properly"
        }
        Write-Logger "WinGet test successful" "INFO"
    }
    catch {
        Write-Logger "WinGet test failed: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show("WinGet is not working properly. Please ensure WinGet is installed and accessible.", "WDCA - WinGet Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    # Temporäres PowerShell-Script erstellen
    $tempScriptPath = Join-Path $env:TEMP "WDCA_WinGet_Install.ps1"

    $scriptContent = @"
# WDCA WinGet Installation Script
# Terminal-Design: Schwarz/Weiß und kompakt
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

Write-Host "WDCA WinGet Installer" -ForegroundColor White
Write-Host "Apps: $($selectedApps.Count) | " -ForegroundColor White -NoNewline
Write-Host "Starting..." -ForegroundColor White
Write-Host ("-" * 50) -ForegroundColor DarkGray

function Write-InstallLog {
    param([string]`$Message, [string]`$Level = "INFO")
    try {
        `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        `$logEntry = "[`$timestamp] [`$Level] [Install] `$Message"
        Add-Content -Path "$($global:sync.logFile)" -Value `$logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # Silent fail for logging
    }
}

Write-InstallLog "=== Starting Installation in new terminal ===" "INFO"

"@

    # Apps zur Installation hinzufügen
    foreach ($app in $selectedApps) {
        $scriptContent += @"

Write-Host "Installing $($app.DisplayName)..." -ForegroundColor White -NoNewline
Write-InstallLog "Installing: $($app.DisplayName) (ID: $($app.WingetId))" "INFO"

try {
    `$installArgs = @(
        "install"
        "--id"
        "$($app.WingetId)"
        "--silent"
        "--accept-source-agreements"
        "--accept-package-agreements"
        "--force"
    )

    # WinGet ausführen
    & winget @installArgs | Out-Null

    `$exitCode = `$LASTEXITCODE

    if (`$exitCode -eq 0) {
        Write-Host " OK" -ForegroundColor White
        Write-InstallLog "SUCCESS: $($app.DisplayName)" "SUCCESS"
    }
    else {
        Write-Host " FAILED (`$exitCode)" -ForegroundColor White
        Write-InstallLog "FAILED: $($app.DisplayName) - Exit Code: `$exitCode" "ERROR"
    }
}
catch {
    Write-Host " ERROR" -ForegroundColor White
    Write-InstallLog "EXCEPTION: $($app.DisplayName) - `$(`$_.Exception.Message)" "ERROR"
}

Start-Sleep -Milliseconds 200

"@
    }

    $scriptContent += @"

Write-Host ("-" * 50) -ForegroundColor DarkGray
Write-Host "Installation completed" -ForegroundColor White
Write-InstallLog "=== Installation Completed ===" "INFO"
Write-Host "Press any key to close..." -ForegroundColor White
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

"@

    try {
        # Script in Temp-Datei schreiben
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        Write-Logger "Created temporary installation script: $tempScriptPath" "INFO"

        # Neues PowerShell-Terminal starten
        $processArgs = @{
            FilePath     = "powershell.exe"
            ArgumentList = @(
                "-NoProfile"
                "-ExecutionPolicy", "Bypass"
                "-File", "`"$tempScriptPath`""
            )
            WindowStyle  = "Normal"
            PassThru     = $true
        }

        $installProcess = Start-Process @processArgs
        Write-Logger "Started installation in new terminal (PID: $($installProcess.Id))" "SUCCESS"

        # Cleanup-Timer für das temporäre Script
        $cleanupTimer = New-Object System.Windows.Threading.DispatcherTimer
        $cleanupTimer.Interval = [TimeSpan]::FromSeconds(10)

        $cleanupTimer.Add_Tick({
                try {
                    if ($installProcess.HasExited) {
                        # Temporäres Script löschen
                        if (Test-Path $tempScriptPath) {
                            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
                            Write-Logger "Cleaned up temporary script" "INFO"
                        }
                        $cleanupTimer.Stop()
                    }
                }
                catch {
                    Write-Logger "Cleanup error: $($_.Exception.Message)" "ERROR"
                    $cleanupTimer.Stop()
                }
            })

        $cleanupTimer.Start()
    }
    catch {
        Write-Logger "Error starting installation terminal: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start installation in new terminal: $($_.Exception.Message)",
            "WDCA - Terminal Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
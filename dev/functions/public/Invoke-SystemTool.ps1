
function Invoke-SystemTool {
    <#
    .SYNOPSIS
        Unified system diagnostic tool runner
    .PARAMETER Tool
        Tool to run (DISM, SFC, CHKDSK)
    #>
    param(
        [ValidateSet("DISM", "SFC", "CHKDSK")]
        [string]$Tool
    )

    Write-Logger "Starting $Tool scan in new terminal" "INFO"

    $tempScriptPath = Join-Path $env:TEMP "WDCA_$($Tool)_Scan.ps1"
    $logPath = Join-Path $env:TEMP "wdca_$($Tool.ToLower()).log"

    # Tool-specific configuration
    $toolConfig = switch ($Tool) {
        "DISM" {
            @{
                Title = "DISM Image Repair Tool"
                Commands = @(
                    @{ Name = "CheckHealth"; Command = "dism.exe /Online /Cleanup-Image /CheckHealth" },
                    @{ Name = "ScanHealth"; Command = "dism.exe /Online /Cleanup-Image /ScanHealth" },
                    @{ Name = "RestoreHealth"; Command = "dism.exe /Online /Cleanup-Image /RestoreHealth" }
                )
            }
        }
        "SFC" {
            @{
                Title = "System File Checker (SFC)"
                Commands = @(
                    @{ Name = "ScanNow"; Command = "sfc.exe /scannow" }
                )
            }
        }
        "CHKDSK" {
            @{
                Title = "CHKDSK Disk Check Tool"
                Commands = @(
                    @{ Name = "CheckDisk"; Command = "chkdsk.exe $env:SystemDrive /f /r" }
                )
            }
        }
    }

    $scriptContent = @"
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

function Write-ToolLog {
    param([string]`$Message, [string]`$Level = "INFO")
    try {
        `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path "$logPath" -Value "[`$timestamp] [`$Level] `$Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host "  WDCA $($toolConfig.Title)" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host ""

Write-ToolLog "$Tool scan started" "INFO"
Write-Host "[INFO] Starting $Tool diagnostics..." -ForegroundColor Cyan
Write-Host ""

try {
    `$overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
"@

    # Add commands based on tool
    $commandIndex = 1
    foreach ($command in $toolConfig.Commands) {
        $scriptContent += @"

    Write-Host "Step $commandIndex/$($toolConfig.Commands.Count): $($command.Name)" -ForegroundColor Yellow
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-ToolLog "Running: $($command.Command)" "INFO"

    `$stepStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Execute command directly using Invoke-Expression for better compatibility
    try {
        `$output = Invoke-Expression "$($command.Command)" 2>&1
        `$exitCode = `$LASTEXITCODE
    } catch {
        `$exitCode = 1
        Write-Host "[ERROR] Command execution failed: `$(`$_.Exception.Message)" -ForegroundColor Red
    }

    `$stepStopwatch.Stop()

    if (`$exitCode -eq 0) {
        Write-Host "[SUCCESS] $($command.Name) completed (`$(`$stepStopwatch.Elapsed.ToString("mm\:ss")))" -ForegroundColor Green
        Write-ToolLog "$($command.Name) completed successfully" "SUCCESS"
    } else {
        Write-Host "[WARNING] $($command.Name) completed with issues (Exit: `$exitCode)" -ForegroundColor Yellow
        Write-ToolLog "$($command.Name) completed with exit code `$exitCode" "WARNING"
    }
    Write-Host ""
"@
        $commandIndex++
    }

    $scriptContent += @"

    `$overallStopwatch.Stop()

    Write-Host ("-" * 50) -ForegroundColor DarkGray
    Write-Host "$Tool scan completed in `$(`$overallStopwatch.Elapsed.ToString("mm\:ss"))" -ForegroundColor Cyan
}
catch {
    Write-Host "[ERROR] $Tool operation failed: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-ToolLog "$Tool error: `$(`$_.Exception.Message)" "ERROR"
}

Write-Host ""
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
Write-ToolLog "$Tool scan completed" "INFO"
Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        Write-Logger "Created $Tool script: $tempScriptPath" "INFO"

        # Start PowerShell with elevated privileges if needed
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = "powershell.exe"
        $processStartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tempScriptPath`""
        $processStartInfo.Verb = "RunAs"  # Request elevation
        $processStartInfo.UseShellExecute = $true
        $processStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal

        $process = [System.Diagnostics.Process]::Start($processStartInfo)

        if ($process) {
            Write-Logger "Started $Tool terminal (PID: $($process.Id))" "SUCCESS"
        } else {
            throw "Failed to start process"
        }

        # Cleanup after completion
        Start-Job -ScriptBlock {
            param($ProcessId, $ScriptPath)
            try {
                $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $proc.WaitForExit() }
                Start-Sleep -Seconds 5
                if (Test-Path $ScriptPath) {
                    Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        } -ArgumentList $process.Id, $tempScriptPath | Out-Null

    }
    catch {
        Write-Logger "Failed to start $Tool`: $($_.Exception.Message)" "ERROR"

        # Show user-friendly error message
        $errorMessage = switch ($_.Exception.Message) {
            { $_ -like "*cancelled*" -or $_ -like "*1223*" } {
                "$Tool requires administrator privileges to run properly. Please click 'Yes' when prompted for elevation."
            }
            default {
                "Failed to start $Tool scan: $($_.Exception.Message)"
            }
        }

        [System.Windows.MessageBox]::Show(
            $errorMessage,
            "WDCA - $Tool Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )

        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WPFApplicationsAsync {
    <#
    .SYNOPSIS
        Unified application installation with multiple execution modes
    .PARAMETER Mode
        Execution mode: Terminal (default), Silent, or Background
    #>
    param(
        [ValidateSet("Terminal", "Silent", "Background")]
        [string]$Mode = "Terminal"
    )

    Write-Logger "Starting application installation (Mode: $Mode)" "INFO"

    # Collect selected applications
    $selectedApps = @()
    if ($global:sync.configs.applications) {
        foreach ($app in $global:sync.configs.applications.PSObject.Properties) {
            $checkboxName = $app.Name
            if ($global:sync[$checkboxName] -and $global:sync[$checkboxName].IsChecked -eq $true) {
                $selectedApps += @{
                    Name = $checkboxName
                    DisplayName = $app.Value.content
                    WingetId = $app.Value.winget
                }
            }
        }
    }

    if ($selectedApps.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "Please select at least one application to install.",
            "WDCA - No Selection",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
        return
    }

    # Confirmation
    $appList = ($selectedApps | ForEach-Object { "• $($_.DisplayName)" }) -join "`n"
    $confirmResult = [System.Windows.MessageBox]::Show(
        "Install $($selectedApps.Count) selected applications?`n`n$appList",
        "WDCA - Confirm Installation",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Application installation cancelled by user" "INFO"
        return
    }

    # Test WinGet availability
    try {
        $null = & winget --version 2>&1
        if ($LASTEXITCODE -ne 0) { throw "WinGet exit code: $LASTEXITCODE" }
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "WinGet is not available. Please ensure WinGet is installed.",
            "WDCA - WinGet Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    # Execute based on mode
    switch ($Mode) {
        "Terminal" { Start-TerminalInstallation -Apps $selectedApps }
        "Silent" { Start-SilentInstallation -Apps $selectedApps }
        "Background" { Start-BackgroundInstallation -Apps $selectedApps }
    }
}

function Start-TerminalInstallation {
    param([array]$Apps)

    $batchScriptPath = Join-Path $env:TEMP "WDCA_WinGet_Install.cmd"
    $logPath = Join-Path $env:TEMP "wdca_winget_install.log"

    $batchContent = @"
@echo off
title WDCA WinGet Installation
color 0F
echo ============================================================
echo Windows Deployment and Configuration Assistant
echo WinGet Application Installation
echo ============================================================
echo.
echo Installing $($Apps.Count) applications...
echo Log file: $logPath
echo.

"@

    foreach ($app in $Apps) {
        $batchContent += @"
echo Installing: $($app.DisplayName)...
winget install --id "$($app.WingetId)" --silent --accept-source-agreements --accept-package-agreements --force
if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] $($app.DisplayName) installed successfully
) else (
    echo [ERROR] $($app.DisplayName) installation failed
)
echo.

"@
    }

    $batchContent += @"
echo Installation completed
echo Press any key to close this window...
pause >nul
"@

    try {
        Set-Content -Path $batchScriptPath -Value $batchContent -Encoding ASCII
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "`"$batchScriptPath`"") -WindowStyle Normal -PassThru

        # Cleanup job
        Start-Job -ScriptBlock {
            param($ProcessId, $BatchPath)
            try {
                $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $proc.WaitForExit() }
                Start-Sleep -Seconds 5
                if (Test-Path $BatchPath) { Remove-Item $BatchPath -Force -ErrorAction SilentlyContinue }
            } catch { }
        } -ArgumentList $process.Id, $batchScriptPath | Out-Null

        Write-Logger "Started terminal installation (PID: $($process.Id))" "SUCCESS"
    }
    catch {
        Write-Logger "Failed to start terminal installation: $($_.Exception.Message)" "ERROR"
        if (Test-Path $batchScriptPath) { Remove-Item $batchScriptPath -Force -ErrorAction SilentlyContinue }
    }
}

function Start-BackgroundInstallation {
    param([array]$Apps)

    $job = Start-Job -ScriptBlock {
        param($appList)
        $results = @{ TotalApps = $appList.Count; Successful = 0; Failed = 0; StartTime = Get-Date }

        foreach ($app in $appList) {
            try {
                $process = Start-Process -FilePath "winget" -ArgumentList @(
                    "install", "--id", $app.WingetId, "--silent",
                    "--accept-source-agreements", "--accept-package-agreements", "--force"
                ) -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) { $results.Successful++ } else { $results.Failed++ }
            }
            catch { $results.Failed++ }
        }

        $results.EndTime = Get-Date
        return $results
    } -ArgumentList $Apps

    # UI update for background job
    if ($global:sync.WPFInstallSelectedApps) {
        $global:sync.WPFInstallSelectedApps.Content = "Installing..."
        $global:sync.WPFInstallSelectedApps.IsEnabled = $false
    }

    # Job completion handler
    Register-ObjectEvent -InputObject $job -EventName StateChanged -Action {
        param($sender, $eventArgs)
        if ($sender.State -eq 'Completed') {
            try {
                $results = Receive-Job -Job $sender
                $global:sync.Form.Dispatcher.Invoke([action]{
                    if ($global:sync.WPFInstallSelectedApps) {
                        $global:sync.WPFInstallSelectedApps.Content = "Install Selected"
                        $global:sync.WPFInstallSelectedApps.IsEnabled = $true
                    }

                    $duration = ($results.EndTime - $results.StartTime).ToString("mm\:ss")
                    [System.Windows.MessageBox]::Show(
                        "Installation completed in $duration`nSuccessful: $($results.Successful)`nFailed: $($results.Failed)",
                        "WDCA - Installation Complete",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                })
            }
            catch { Write-Logger "Error in completion handler: $($_.Exception.Message)" "ERROR" }
            finally {
                Remove-Job -Job $sender -Force -ErrorAction SilentlyContinue
                Unregister-Event -SourceIdentifier $eventArgs.SourceIdentifier -ErrorAction SilentlyContinue
            }
        }
    } | Out-Null

    Write-Logger "Background installation job started" "INFO"
}

function Invoke-WPFUpdateApps {
    <#
    .SYNOPSIS
        Updates all applications via WinGet in terminal
    #>
    Write-Logger "Starting application updates" "INFO"

    $confirmResult = [System.Windows.MessageBox]::Show(
        "Update all applications using WinGet?",
        "WDCA - Confirm Updates",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Updates cancelled by user" "INFO"
        return
    }

    $tempScriptPath = Join-Path $env:TEMP "WDCA_AppUpdate.ps1"
    $scriptContent = @"
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  WDCA Application Updates" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

try {
    `$startTime = Get-Date
    Write-Host "Starting update process..." -ForegroundColor Cyan
    winget upgrade --all --silent --accept-source-agreements --accept-package-agreements

    `$duration = ((Get-Date) - `$startTime).ToString("mm\:ss")
    Write-Host ""
    Write-Host "Update process completed in `$duration" -ForegroundColor Green
}
catch {
    Write-Host "Update failed: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started update process (PID: $($process.Id))" "SUCCESS"

        # Cleanup
        Start-Job -ScriptBlock {
            param($ProcessId, $ScriptPath)
            try {
                $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $proc.WaitForExit() }
                Start-Sleep -Seconds 5
                if (Test-Path $ScriptPath) { Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue }
            } catch { }
        } -ArgumentList $process.Id, $tempScriptPath | Out-Null

    }
    catch {
        Write-Logger "Failed to start updates: $($_.Exception.Message)" "ERROR"
        if (Test-Path $tempScriptPath) { Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-WPFListAppUpdates {
    <#
    .SYNOPSIS
        Lists available application updates
    #>
    Write-Logger "Checking for application updates" "INFO"

    $tempScriptPath = Join-Path $env:TEMP "WDCA_UpdateCheck.ps1"
    $scriptContent = @"
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  WDCA Update Scanner" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "Scanning for updates..." -ForegroundColor Cyan
    `$output = winget upgrade --include-unknown 2>&1

    Write-Host ""
    Write-Host "Available Updates:" -ForegroundColor Yellow
    Write-Host ("-" * 30) -ForegroundColor DarkGray

    `$updateCount = 0
    foreach (`$line in `$output) {
        if (`$line -match "^[A-Z].*[\d\.].*[\d\.].*winget" -and `$line -notmatch "Name.*Version") {
            `$updateCount++
            Write-Host "[`$updateCount] `$line" -ForegroundColor Green
        }
    }

    if (`$updateCount -eq 0) {
        Write-Host "All applications are up to date!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Found `$updateCount updates available" -ForegroundColor Cyan
        Write-Host "Run 'winget upgrade --all' to update all" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error checking updates: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started update check (PID: $($process.Id))" "SUCCESS"

        # Cleanup
        Start-Job -ScriptBlock {
            param($ProcessId, $ScriptPath)
            try {
                $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $proc.WaitForExit() }
                Start-Sleep -Seconds 5
                if (Test-Path $ScriptPath) { Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue }
            } catch { }
        } -ArgumentList $process.Id, $tempScriptPath | Out-Null

    }
    catch {
        Write-Logger "Failed to start update check: $($_.Exception.Message)" "ERROR"
        if (Test-Path $tempScriptPath) { Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue }
    }
}

function Clear-WDCARecycleBin {
    <#
    .SYNOPSIS
        Empties the recycle bin using multiple fallback methods
    #>
    try {
        Write-Logger "Clearing recycle bin" "INFO"

        # Method 1: COM Shell (primary)
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(0xA)
            if ($recycleBin -and $recycleBin.Items().Count -gt 0) {
                $recycleBin.InvokeVerb("Empty")
                Start-Sleep -Seconds 2
                Write-Logger "Recycle bin cleared via COM" "SUCCESS"
                return "Recycle bin emptied successfully"
            } else {
                return "Recycle bin was already empty"
            }
        }
        catch {
            Write-Logger "COM method failed: $($_.Exception.Message)" "WARNING"
        }
        finally {
            if ($shell) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null }
        }

        # Method 2: rundll32 fallback
        try {
            $process = Start-Process -FilePath "rundll32.exe" -ArgumentList "shell32.dll,SHEmptyRecycleBinW" -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -eq 0) {
                Write-Logger "Recycle bin cleared via rundll32" "SUCCESS"
                return "Recycle bin emptied successfully"
            }
        }
        catch {
            Write-Logger "rundll32 method failed: $($_.Exception.Message)" "WARNING"
        }

        return "Could not empty recycle bin - manual intervention may be required"
    }
    catch {
        Write-Logger "Error clearing recycle bin: $($_.Exception.Message)" "ERROR"
        return "Error emptying recycle bin"
    }
}

function Clear-TemporaryFiles {
    <#
    .SYNOPSIS
        Clears temporary files from standard locations
    #>
    $totalCleaned = 0
    $locations = @(
        @{Path = $env:TEMP; Name = "User Temp"},
        @{Path = "$env:SystemRoot\Temp"; Name = "System Temp"},
        @{Path = "$env:LocalAppData\Temp"; Name = "Local AppData Temp"}
    )

    foreach ($location in $locations) {
        if (-not (Test-Path $location.Path)) { continue }

        try {
            $files = Get-ChildItem -Path $location.Path -Recurse -File -ErrorAction SilentlyContinue
            $sizeBefore = ($files | Measure-Object -Property Length -Sum).Sum

            $removed = 0
            foreach ($file in $files) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $removed++
                }
                catch { }
            }

            $remainingFiles = Get-ChildItem -Path $location.Path -Recurse -File -ErrorAction SilentlyContinue
            $sizeAfter = ($remainingFiles | Measure-Object -Property Length -Sum).Sum
            $cleaned = $sizeBefore - $sizeAfter
            $totalCleaned += $cleaned

            Write-Logger "Cleaned $($location.Name) - $removed files, $([math]::Round($cleaned / 1MB, 2)) MB" "INFO"
        }
        catch {
            Write-Logger "Error cleaning $($location.Name): $($_.Exception.Message)" "ERROR"
        }
    }

    return "$([math]::Round($totalCleaned / 1MB, 2)) MB cleaned"
}

function Clear-EventLogs {
    <#
    .SYNOPSIS
        Clears Windows Event Logs
    #>
    try {
        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 }
        $clearedCount = 0

        foreach ($log in $logs) {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
                $clearedCount++
            }
            catch { }
        }

        Write-Logger "Cleared $clearedCount event logs" "INFO"
        return "$clearedCount logs cleared"
    }
    catch {
        Write-Logger "Error clearing event logs: $($_.Exception.Message)" "WARNING"
        return "Error clearing logs"
    }
}

# System Setup wrappers
function Invoke-WPFSystemSetup {
    param([ValidateSet("Network", "RDP")][string]$Action)

    switch ($Action) {
        "Network" { Invoke-NetworkConfiguration }
        "RDP" { Invoke-RDPConfiguration }
    }
}

function Invoke-SystemDiagnosticsAsync {
    Write-Logger "Starting comprehensive system diagnostics" "INFO"

    $confirmResult = [System.Windows.MessageBox]::Show(
        "Run comprehensive system diagnostics? This will run DISM, SFC, and CHKDSK sequentially.",
        "WDCA - System Diagnostics",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -eq [System.Windows.MessageBoxResult]::Yes) {
        Invoke-SystemTool -Tool "DISM"
        Start-Sleep -Seconds 2
        Invoke-SystemTool -Tool "SFC"
        Start-Sleep -Seconds 2
        Invoke-SystemTool -Tool "CHKDSK"
    }
}

function Invoke-PreCloneCleanup {
    Write-Logger "Starting pre-clone cleanup" "INFO"

    $cleanTemp = if ($sync.WPFCleanupTemp) { $sync.WPFCleanupTemp.IsChecked } else { $true }
    $cleanLogs = if ($sync.WPFCleanupLogs) { $sync.WPFCleanupLogs.IsChecked } else { $true }
    $cleanRecycle = if ($sync.WPFCleanupRecycle) { $sync.WPFCleanupRecycle.IsChecked } else { $true }

    $results = @()
    if ($cleanTemp) { $results += "Temp Files: $(Clear-TemporaryFiles)" }
    if ($cleanLogs) { $results += "Event Logs: $(Clear-EventLogs)" }
    if ($cleanRecycle) { $results += "Recycle Bin: $(Clear-WDCARecycleBin)" }

    [System.Windows.MessageBox]::Show(
        "Cleanup completed!`n`n" + ($results -join "`n"),
        "WDCA - Cleanup Complete",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    )
}

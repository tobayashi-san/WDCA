

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
            }
            else {
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
        @{Path = $env:TEMP; Name = "User Temp" },
        @{Path = "$env:SystemRoot\Temp"; Name = "System Temp" },
        @{Path = "$env:LocalAppData\Temp"; Name = "Local AppData Temp" }
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

function Invoke-WPFApplicationsAsync {
    <#
    .SYNOPSIS
        Application installation running in background with UI updates
    #>
    param(
        [ValidateSet("Background", "Silent")]
        [string]$Mode = "Background"
    )

    Write-Logger "Starting background application installation" "INFO"

    # Collect selected applications
    $selectedApps = @()
    if ($global:sync.configs.applications) {
        foreach ($app in $global:sync.configs.applications.PSObject.Properties) {
            $checkboxName = $app.Name
            if ($global:sync[$checkboxName] -and $global:sync[$checkboxName].IsChecked -eq $true) {
                $selectedApps += @{
                    Name        = $checkboxName
                    DisplayName = $app.Value.content
                    WingetId    = $app.Value.winget
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
        "Install $($selectedApps.Count) selected applications in background?`n`n$appList`n`nInstallation will run silently while UI remains responsive.",
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

    # Start background installation
    Start-BackgroundInstallation -Apps $selectedApps
}

function Start-BackgroundInstallation {
    param([array]$Apps)

    Write-Logger "Starting silent background installation of $($Apps.Count) applications" "INFO"

    # UI vorbereiten
    $global:sync.Form.Dispatcher.Invoke([action] {
            if ($global:sync.WPFInstallSelectedApps) {
                $global:sync.WPFInstallSelectedApps.Content = "Installing... (0/$($Apps.Count))"
                $global:sync.WPFInstallSelectedApps.IsEnabled = $false
            }
            if ($global:sync.WPFProgressBar) {
                $global:sync.WPFProgressBar.Visibility = "Visible"
                $global:sync.WPFProgressBar.IsIndeterminate = $false
                $global:sync.WPFProgressBar.Value = 0
            }
        })

    Set-WDCAStatus "Installing applications... (0/$($Apps.Count))"

    # Hintergrundjob mit verbesserter Fehlerbehandlung
    $job = Start-Job -ScriptBlock {
        param($appList)

        try {
            $results = @{
                Type       = "FinalResult"
                TotalApps  = $appList.Count
                Successful = 0
                Failed     = 0
                Details    = @()
                StartTime  = Get-Date
            }

            Write-Output "JOB_STARTED"

            for ($i = 0; $i -lt $appList.Count; $i++) {
                $app = $appList[$i]
                $index = $i + 1

                Write-Output "Starting app $index of $($appList.Count): $($app.DisplayName)"

                try {
                    Write-Output "Installing: $($app.DisplayName)"

                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = "winget.exe"
                    $psi.Arguments = "install --id `"$($app.WingetId)`" --silent --accept-source-agreements --accept-package-agreements --force"
                    $psi.UseShellExecute = $false
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.CreateNoWindow = $true
                    $psi.WorkingDirectory = $env:TEMP

                    Write-Output "Starting process with args: $($psi.Arguments)"

                    $process = [System.Diagnostics.Process]::Start($psi)
                    $timeoutMs = 300000  # 5 Minuten Timeout

                    if ($process.WaitForExit($timeoutMs)) {
                        $stdout = $process.StandardOutput.ReadToEnd()
                        $stderr = $process.StandardError.ReadToEnd()
                        $exitCode = $process.ExitCode

                        Write-Output "Process completed with exit code: $exitCode"
                        if ($stdout) { Write-Output "STDOUT: $stdout" }
                        if ($stderr) { Write-Output "STDERR: $stderr" }

                        $isSuccess = $false
                        if ($exitCode -eq 0) {
                            $isSuccess = $true
                        }
                        elseif ($exitCode -eq -1978335189) {
                            $isSuccess = $true
                            Write-Output "App already installed"
                        }
                        elseif ($exitCode -eq -1978335212) {
                            $isSuccess = $true
                            Write-Output "No newer version available"
                        }
                        elseif ($stdout -like "*successfully installed*" -or $stdout -like "*Installation completed successfully*") {
                            $isSuccess = $true
                            Write-Output "Success detected via output analysis"
                        }

                        if ($isSuccess) {
                            $results.Successful++
                            $results.Details += "✓ $($app.DisplayName) - Success"
                            Write-Output "SUCCESS: $($app.DisplayName)"
                        }
                        else {
                            $results.Failed++
                            $errorMsg = if ($stderr) { $stderr.Trim() } else { "Exit code: $exitCode" }
                            $results.Details += "✗ $($app.DisplayName) - $errorMsg"
                            Write-Output "FAILED: $($app.DisplayName) - $errorMsg"
                        }
                    }
                    else {
                        try {
                            $process.Kill()
                        }
                        catch {

                        }
                        $results.Failed++
                        $results.Details += "✗ $($app.DisplayName) - Installation timeout"
                        Write-Output "TIMEOUT: $($app.DisplayName)"
                    }
                }
                catch {
                    $results.Failed++
                    $errorMsg = $_.Exception.Message
                    $results.Details += "✗ $($app.DisplayName) - Error: $errorMsg"
                    Write-Output "EXCEPTION: $($app.DisplayName) - $errorMsg"
                }
            }

            $results.EndTime = Get-Date
            $results.Duration = ($results.EndTime - $results.StartTime).ToString("mm':'ss")

            $finalJson = $results | ConvertTo-Json -Depth 3 -Compress
            Write-Output "FINAL_RESULT:$finalJson"
            Write-Output "JOB_COMPLETED"

            return "JOB_SUCCESS"
        }
        catch {
            Write-Output "CRITICAL_ERROR: $($_.Exception.Message)"
            Write-Error $_.Exception.Message
            throw
        }
    } -ArgumentList @($Apps)

    # Timer für Fortschritt mit verbesserter Nachrichtenverarbeitung
    $progressTimer = New-Object System.Windows.Threading.DispatcherTimer
    $progressTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $processedMessages = @()

    $progressTimer.Add_Tick({
            try {
                $jobState = $job.State
                Write-Logger "Job State: $jobState" "DEBUG"

                if ($jobState -eq "Running") {
                    $outputs = Receive-Job -Job $job -Keep

                    foreach ($output in $outputs) {
                        if ($output -notin $processedMessages) {
                            $processedMessages += $output
                            # Reduced DEBUG logging - nur bei wichtigen Events
                            if ($output -like "PROGRESS:*" -or $output -like "SUCCESS:*" -or $output -like "FAILED:*") {
                                Write-Logger "Job Output: $output" "DEBUG"
                            }

                            # Progress-Nachrichten verarbeiten
                            if ($output -like "PROGRESS:*") {
                                try {
                                    $progressData = $output.Replace("PROGRESS:", "") | ConvertFrom-Json

                                    $global:sync.Form.Dispatcher.Invoke([action] {
                                            if ($global:sync.WPFInstallSelectedApps) {
                                                $global:sync.WPFInstallSelectedApps.Content = "Installing... ($($progressData.Index)/$($progressData.Total))"
                                            }
                                            if ($global:sync.WPFProgressBar) {
                                                $global:sync.WPFProgressBar.Value = $progressData.PercentComplete
                                            }
                                        })

                                    Set-WDCAStatus "Installing $($progressData.CurrentApp) ($($progressData.Index)/$($progressData.Total))"
                                    Write-Logger "Progress: $($progressData.CurrentApp) ($($progressData.Index)/$($progressData.Total))" "INFO"
                                }
                                catch {
                                    Write-Logger "Error parsing progress: $($_.Exception.Message)" "WARNING"
                                }
                            }
                        }
                    }
                }
                elseif ($jobState -eq "Completed") {
                    $progressTimer.Stop()
                    Write-Logger "Job completed successfully" "INFO"

                    try {
                        $allOutputs = Receive-Job -Job $job -ErrorAction SilentlyContinue
                        Write-Logger "Retrieved $($allOutputs.Count) outputs from completed job" "DEBUG"

                        # Final Result aus JSON extrahieren
                        $finalResult = $null
                        $jobCompletedFound = $false

                        foreach ($output in $allOutputs) {
                            if ($output -eq "JOB_COMPLETED" -or $output -eq "JOB_SUCCESS") {
                                $jobCompletedFound = $true
                            }
                            if ($output -like "FINAL_RESULT:*") {
                                try {
                                    $finalResult = $output.Replace("FINAL_RESULT:", "") | ConvertFrom-Json
                                    Write-Logger "Final result parsed successfully" "DEBUG"
                                }
                                catch {
                                    Write-Logger "Error parsing final result: $($_.Exception.Message)" "ERROR"
                                }
                            }
                        }

                        if ($finalResult) {
                            Write-Logger "Installation completed: $($finalResult.Successful) successful, $($finalResult.Failed) failed in $($finalResult.Duration)" "SUCCESS"

                            # Success message erstellen
                            $summaryMessage = "Application installation completed in $($finalResult.Duration)`n`n"
                            $summaryMessage += "Successfully installed: $($finalResult.Successful)`n"
                            $summaryMessage += "Failed: $($finalResult.Failed)`n"
                            $summaryMessage += "Total processed: $($finalResult.TotalApps)"

                            if ($finalResult.Details -and $finalResult.Details.Count -gt 0) {
                                $summaryMessage += "`n`nDetails:`n" + ($finalResult.Details -join "`n")
                            }

                            # Icon und Titel basierend auf Ergebnis
                            if ($finalResult.Successful -eq $finalResult.TotalApps) {
                                $icon = [System.Windows.MessageBoxImage]::Information
                                $title = "WDCA - Installation Complete"
                            }
                            elseif ($finalResult.Successful -gt 0) {
                                $icon = [System.Windows.MessageBoxImage]::Warning
                                $title = "WDCA - Partial Success"
                            }
                            else {
                                $icon = [System.Windows.MessageBoxImage]::Error
                                $title = "WDCA - Installation Failed"
                            }

                            [System.Windows.MessageBox]::Show($summaryMessage, $title, [System.Windows.MessageBoxButton]::OK, $icon)
                        }
                        elseif ($jobCompletedFound) {
                            Write-Logger "Job completed but no final result - using fallback analysis" "WARNING"

                            # Fallback - zähle SUCCESS/FAILED Nachrichten
                            $successCount = ($allOutputs | Where-Object { $_ -like "SUCCESS:*" }).Count
                            $failedCount = ($allOutputs | Where-Object { $_ -like "FAILED:*" -or $_ -like "EXCEPTION:*" -or $_ -like "TIMEOUT:*" }).Count
                            $totalProcessed = $successCount + $failedCount

                            if ($totalProcessed -gt 0) {
                                $fallbackMessage = "Installation completed:`n`nSuccessfully installed: $successCount`nFailed: $failedCount`nTotal processed: $totalProcessed"

                                $fallbackIcon = if ($successCount -eq $totalProcessed) {
                                    [System.Windows.MessageBoxImage]::Information
                                }
                                elseif ($successCount -gt 0) {
                                    [System.Windows.MessageBoxImage]::Warning
                                }
                                else {
                                    [System.Windows.MessageBoxImage]::Error
                                }

                                [System.Windows.MessageBox]::Show($fallbackMessage, "WDCA - Installation Complete", [System.Windows.MessageBoxButton]::OK, $fallbackIcon)
                                Write-Logger "Fallback analysis: $successCount successful, $failedCount failed" "INFO"
                            }
                            else {
                                [System.Windows.MessageBox]::Show(
                                    "Installation process completed. Please verify if the application was installed successfully.",
                                    "WDCA - Installation Complete",
                                    [System.Windows.MessageBoxButton]::OK,
                                    [System.Windows.MessageBoxImage]::Information
                                )
                            }
                        }
                        else {
                            Write-Logger "Job completed but no completion markers found" "ERROR"
                            [System.Windows.MessageBox]::Show(
                                "Installation process may have completed but status is unclear. Please check if the application was installed.",
                                "WDCA - Installation Status Unknown",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Warning
                            )
                        }
                    }
                    catch {
                        Write-Logger "Error processing completed job: $($_.Exception.Message)" "ERROR"
                        [System.Windows.MessageBox]::Show(
                            "Installation completed but there was an error processing the results. Check if the application was installed successfully.",
                            "WDCA - Installation Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                    }

                    # UI zurücksetzen
                    $global:sync.Form.Dispatcher.Invoke([action] {
                            if ($global:sync.WPFInstallSelectedApps) {
                                $global:sync.WPFInstallSelectedApps.Content = "Install Selected"
                                $global:sync.WPFInstallSelectedApps.IsEnabled = $true
                            }
                            if ($global:sync.WPFProgressBar) {
                                $global:sync.WPFProgressBar.Value = 100
                                # Progress bar nach kurzer Zeit ausblenden
                                $hideTimer = New-Object System.Windows.Threading.DispatcherTimer
                                $hideTimer.Interval = [TimeSpan]::FromSeconds(1)
                                $hideTimer.Add_Tick({
                                        $global:sync.WPFProgressBar.Visibility = "Collapsed"
                                        $this.Stop()
                                    })
                                $hideTimer.Start()
                            }
                        })

                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    Set-WDCAStatus "Ready - Installation completed"
                }
                elseif ($jobState -eq "Failed") {
                    $progressTimer.Stop()
                    Write-Logger "Job marked as failed - analyzing outputs" "ERROR"

                    try {
                        $allOutputs = Receive-Job -Job $job -ErrorAction SilentlyContinue
                        $jobErrors = $job.ChildJobs[0].Error | ForEach-Object { $_.ToString() }

                        Write-Logger "Failed job outputs: $($allOutputs -join '; ')" "DEBUG"
                        Write-Logger "Failed job errors: $($jobErrors -join '; ')" "ERROR"

                        # Prüfen ob es ein CRITICAL_ERROR gab
                        $criticalErrors = $allOutputs | Where-Object { $_ -like "CRITICAL_ERROR:*" }

                        if ($criticalErrors.Count -gt 0) {
                            $errorMsg = ($criticalErrors | ForEach-Object { $_.Replace("CRITICAL_ERROR: ", "") }) -join "; "
                            [System.Windows.MessageBox]::Show(
                                "Installation failed with critical error:`n`n$errorMsg",
                                "WDCA - Installation Failed",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Error
                            )
                        }
                        else {
                            # Möglicherweise ist der Job nur wegen einem winget Exit-Code als failed markiert
                            # Schauen ob trotzdem SUCCESS-Nachrichten da sind
                            $successCount = ($allOutputs | Where-Object { $_ -like "SUCCESS:*" }).Count

                            if ($successCount -gt 0) {
                                Write-Logger "Job marked as failed but found $successCount successes - possible false positive" "WARNING"
                                [System.Windows.MessageBox]::Show(
                                    "Installation may have succeeded despite job failure status. Please check if the application was installed.",
                                    "WDCA - Installation Status Unclear",
                                    [System.Windows.MessageBoxButton]::OK,
                                    [System.Windows.MessageBoxImage]::Warning
                                )
                            }
                            else {
                                [System.Windows.MessageBox]::Show(
                                    "Installation job failed. Check logs for details.",
                                    "WDCA - Installation Failed",
                                    [System.Windows.MessageBoxButton]::OK,
                                    [System.Windows.MessageBoxImage]::Error
                                )
                            }
                        }
                    }
                    catch {
                        Write-Logger "Could not analyze failed job: $($_.Exception.Message)" "ERROR"
                        [System.Windows.MessageBox]::Show(
                            "Installation failed and error analysis also failed. Check logs for details.",
                            "WDCA - Installation Failed",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }

                    # UI zurücksetzen
                    $global:sync.Form.Dispatcher.Invoke([action] {
                            if ($global:sync.WPFInstallSelectedApps) {
                                $global:sync.WPFInstallSelectedApps.Content = "Install Selected"
                                $global:sync.WPFInstallSelectedApps.IsEnabled = $true
                            }
                            if ($global:sync.WPFProgressBar) {
                                $global:sync.WPFProgressBar.Visibility = "Collapsed"
                            }
                        })

                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    Set-WDCAStatus "Ready - Installation failed"
                }
            }
            catch {
                $progressTimer.Stop()
                Write-Logger "Error in progress timer: $($_.Exception.Message)" "ERROR"

                # UI zurücksetzen bei Fehler
                try {
                    $global:sync.Form.Dispatcher.Invoke([action] {
                            if ($global:sync.WPFInstallSelectedApps) {
                                $global:sync.WPFInstallSelectedApps.Content = "Install Selected"
                                $global:sync.WPFInstallSelectedApps.IsEnabled = $true
                            }
                            if ($global:sync.WPFProgressBar) {
                                $global:sync.WPFProgressBar.Visibility = "Collapsed"
                            }
                        })
                }
                catch {
                    Write-Logger "Error resetting UI: $($_.Exception.Message)" "ERROR"
                }

                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                Set-WDCAStatus "Ready - Installation error"
            }
        }.GetNewClosure())

    $progressTimer.Start()
    Write-Logger "Background installation job started with progress monitoring" "INFO"
}

function Invoke-WPFListAppUpdates {
    <#
    .SYNOPSIS
        Lists available application updates in background with improved formatting
    #>
    Write-Logger "Checking for application updates in background" "INFO"

    # Update UI state
    if ($global:sync.WPFListAppUpdate) {
        $global:sync.WPFListAppUpdate.Content = "Checking..."
        $global:sync.WPFListAppUpdate.IsEnabled = $false
    }

    if ($global:sync.WPFProgressBar) {
        $global:sync.WPFProgressBar.Dispatcher.Invoke([action] {
                $global:sync.WPFProgressBar.Visibility = "Visible"
                $global:sync.WPFProgressBar.IsIndeterminate = $true
            })
    }

    Set-WDCAStatus "Scanning for application updates..."

    # Create background job for update checking
    $updateJob = Start-Job -ScriptBlock {
        try {
            # Execute winget upgrade command
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = "winget.exe"
            $processInfo.Arguments = "upgrade --include-unknown"
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true

            $process = [System.Diagnostics.Process]::Start($processInfo)

            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()

            # Wait for process to complete with timeout
            $timeoutReached = -not $process.WaitForExit(60000) # 1 minute timeout

            if ($timeoutReached) {
                $process.Kill()
                throw "Update check timeout after 1 minute"
            }

            $results = @{
                Success  = $process.ExitCode -eq 0
                Output   = $output
                Error    = $errorOutput
                ExitCode = $process.ExitCode
            }

            # Improved parsing with fallback to original method
            if ($results.Success -and $results.Output) {
                $lines = $results.Output -split "`r?`n" | Where-Object { $_.Trim() -ne "" }

                # Method 1: Try improved parsing
                $headerFound = $false
                $updateEntries = @()

                foreach ($line in $lines) {
                    $trimmedLine = $line.Trim()

                    # Skip until we find the header line
                    if ($trimmedLine -match "Name\s+Id\s+Version\s+Available\s+Source") {
                        $headerFound = $true
                        continue
                    }

                    # Skip separator lines
                    if ($trimmedLine -match "^-+\s*$" -or $trimmedLine -eq "") {
                        continue
                    }

                    # Process update lines after header
                    if ($headerFound -and $trimmedLine -match "winget\s*$") {
                        try {
                            # Split line into components (winget output can be tricky with spacing)
                            $fields = $trimmedLine -split '\s{2,}' # Split on multiple spaces

                            if ($fields.Count -ge 4) {
                                $name = $fields[0].Trim()
                                $id = $fields[1].Trim()
                                $currentVersion = $fields[2].Trim()
                                $availableVersion = $fields[3].Trim().Replace(" winget", "")

                                # Create formatted entry
                                $formattedEntry = "$name`n  ID: $id`n  Current: $currentVersion → Available: $availableVersion"
                                $updateEntries += $formattedEntry
                            }
                            else {
                                # Fallback: try different parsing approach
                                $parts = $trimmedLine -split '\s+' | Where-Object { $_ -ne "" }
                                if ($parts.Count -ge 4) {
                                    $name = $parts[0]
                                    # ID is often the second-to-last or third-to-last item
                                    $availableVersion = $parts[-1].Replace("winget", "").Trim()
                                    $currentVersion = $parts[-2]
                                    $id = $parts[-3]

                                    if ($parts.Count -gt 4) {
                                        # Rebuild name from remaining parts
                                        $nameEnd = $parts.Length - 3
                                        $name = ($parts[0..($nameEnd - 1)] -join " ")
                                    }

                                    $formattedEntry = "$name`n  ID: $id`n  Current: $currentVersion → Available: $availableVersion"
                                    $updateEntries += $formattedEntry
                                }
                                else {
                                    # Add raw line as backup
                                    $updateEntries += $trimmedLine
                                }
                            }
                        }
                        catch {
                            # If parsing fails, use the raw line
                            $updateEntries += $trimmedLine
                        }
                    }
                }

                # Method 2: Fallback to original simple parsing if no updates found
                if ($updateEntries.Count -eq 0) {
                    Write-Output "DEBUG: Improved parsing found no updates, falling back to original method"

                    $simpleUpdateLines = $results.Output -split "`n" | Where-Object {
                        $_ -match "^[A-Za-z0-9].*[\d\.].*[\d\.].*winget" -and $_ -notmatch "Name.*Version"
                    }

                    if ($simpleUpdateLines.Count -gt 0) {
                        Write-Output "DEBUG: Original parsing found $($simpleUpdateLines.Count) updates"
                        # Use original lines but try to format them better
                        foreach ($line in $simpleUpdateLines) {
                            $parts = $line.Trim() -split '\s+' | Where-Object { $_ -ne "" }
                            if ($parts.Count -ge 3) {
                                $name = $parts[0]
                                $lastPart = $parts[-1]
                                if ($lastPart -eq "winget") {
                                    $available = $parts[-2]
                                    $current = if ($parts.Count -gt 3) { $parts[-3] } else { "Unknown" }
                                }
                                else {
                                    $available = $lastPart.Replace("winget", "").Trim()
                                    $current = $parts[-2]
                                }

                                $formattedEntry = "$name`n  Current: $current → Available: $available"
                                $updateEntries += $formattedEntry
                            }
                            else {
                                # Fallback to raw line
                                $updateEntries += $line.Trim()
                            }
                        }
                    }
                }

                $results.UpdateCount = $updateEntries.Count
                $results.Updates = $updateEntries

                # Debug output
                Write-Output "DEBUG: Final update count: $($results.UpdateCount)"
            }
            else {
                $results.UpdateCount = 0
                $results.Updates = @()
                Write-Output "DEBUG: No output or process failed"
            }

            return $results
        }
        catch {
            return @{
                Success     = $false
                Error       = $_.Exception.Message
                UpdateCount = 0
                Updates     = @()
            }
        }
    }

    # Monitor the update job with reduced timer frequency
    $updateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $updateTimer.Interval = [TimeSpan]::FromSeconds(2)

    $updateTimer.Add_Tick({
            try {
                if ($updateJob.State -eq 'Completed') {
                    $this.Stop()

                    try {
                        $results = Receive-Job -Job $updateJob

                        # Update UI
                        $global:sync.Form.Dispatcher.Invoke([action] {
                                if ($global:sync.WPFListAppUpdate) {
                                    $global:sync.WPFListAppUpdate.Content = "List All Updates"
                                    $global:sync.WPFListAppUpdate.IsEnabled = $true
                                }
                                if ($global:sync.WPFProgressBar) {
                                    $global:sync.WPFProgressBar.Visibility = "Collapsed"
                                }
                            })

                        if ($results.Success) {
                            if ($results.UpdateCount -gt 0) {
                                # Join formatted entries with double newlines for better readability
                                $updateList = $results.Updates -join "`n`n"
                                $message = "Found $($results.UpdateCount) available updates:`n`n$updateList`n`n`nUse 'Update All Apps' to install all updates."
                                $icon = [System.Windows.MessageBoxImage]::Information
                                $title = "WDCA - Updates Available"

                                Write-Logger "Found $($results.UpdateCount) available updates" "INFO"
                            }
                            else {
                                $message = "All applications are up to date!"
                                $icon = [System.Windows.MessageBoxImage]::Information
                                $title = "WDCA - No Updates"

                                Write-Logger "No application updates available" "INFO"
                            }
                        }
                        else {
                            $message = "Error checking for updates: $($results.Error)"
                            $icon = [System.Windows.MessageBoxImage]::Error
                            $title = "WDCA - Update Check Failed"

                            Write-Logger "Update check failed: $($results.Error)" "ERROR"
                        }

                        [System.Windows.MessageBox]::Show($message, $title, [System.Windows.MessageBoxButton]::OK, $icon)
                        Set-WDCAStatus "Ready - Update check completed"
                    }
                    catch {
                        Write-Logger "Error processing update results: $($_.Exception.Message)" "ERROR"
                        Set-WDCAStatus "Ready - Update check completed with errors"
                    }
                    finally {
                        Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue
                    }
                }
                elseif ($updateJob.State -eq 'Failed') {
                    $this.Stop()

                    Write-Logger "Update check job failed" "ERROR"

                    $global:sync.Form.Dispatcher.Invoke([action] {
                            if ($global:sync.WPFListAppUpdate) {
                                $global:sync.WPFListAppUpdate.Content = "List All Updates"
                                $global:sync.WPFListAppUpdate.IsEnabled = $true
                            }
                            if ($global:sync.WPFProgressBar) {
                                $global:sync.WPFProgressBar.Visibility = "Collapsed"
                            }
                        })

                    [System.Windows.MessageBox]::Show(
                        "Update check failed. Please try again or check your internet connection.",
                        "WDCA - Update Check Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )

                    Set-WDCAStatus "Ready - Update check failed"
                    Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Logger "Error in update timer: $($_.Exception.Message)" "ERROR"
                $this.Stop()
                Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue
            }
        }.GetNewClosure())

    $updateTimer.Start()
    Write-Logger "Background update check started" "INFO"
}

function Invoke-WPFUpdateApps {
    <#
    .SYNOPSIS
        Updates all applications in background
    #>
    Write-Logger "Starting background application updates" "INFO"

    $confirmResult = [System.Windows.MessageBox]::Show(
        "Update all applications using WinGet in background?`n`nThis will update all installed applications silently while keeping the UI responsive.",
        "WDCA - Confirm Updates",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Updates cancelled by user" "INFO"
        return
    }

    # Update UI state
    if ($global:sync.WPFUpdateApps) {
        $global:sync.WPFUpdateApps.Content = "Updating..."
        $global:sync.WPFUpdateApps.IsEnabled = $false
    }

    if ($global:sync.WPFProgressBar) {
        $global:sync.WPFProgressBar.Dispatcher.Invoke([action] {
                $global:sync.WPFProgressBar.Visibility = "Visible"
                $global:sync.WPFProgressBar.IsIndeterminate = $true
            })
    }

    Set-WDCAStatus "Updating all applications..."

    # Create background job for updates
    $updateJob = Start-Job -ScriptBlock {
        try {
            $startTime = Get-Date

            # Execute winget upgrade command
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = "winget.exe"
            $processInfo.Arguments = "upgrade --all --silent --accept-source-agreements --accept-package-agreements"
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true

            $process = [System.Diagnostics.Process]::Start($processInfo)

            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()

            # Wait for process to complete with timeout (15 minutes)
            $timeoutReached = -not $process.WaitForExit(900000)

            if ($timeoutReached) {
                $process.Kill()
                throw "Update process timeout after 15 minutes"
            }

            $endTime = Get-Date
            $duration = ($endTime - $startTime).ToString("mm':'ss")

            return @{
                Success   = $process.ExitCode -eq 0 -or $process.ExitCode -eq -1978335188
                Output    = $output
                Error     = $errorOutput
                ExitCode  = $process.ExitCode
                Duration  = $duration
                StartTime = $startTime
                EndTime   = $endTime
            }
        }
        catch {
            return @{
                Success  = $false
                Error    = $_.Exception.Message
                Duration = "00:00"
                ExitCode = -1
            }
        }
    }

    # Monitor the update job
    $updateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $updateTimer.Interval = [TimeSpan]::FromSeconds(2)

    $updateTimer.Add_Tick({
            try {
                if ($updateJob.State -eq 'Completed') {
                    $this.Stop()

                    try {
                        $results = Receive-Job -Job $updateJob

                        # Update UI
                        $global:sync.Form.Dispatcher.Invoke([action] {
                                if ($global:sync.WPFUpdateApps) {
                                    $global:sync.WPFUpdateApps.Content = "Update All Apps"
                                    $global:sync.WPFUpdateApps.IsEnabled = $true
                                }
                                if ($global:sync.WPFProgressBar) {
                                    $global:sync.WPFProgressBar.Visibility = "Collapsed"
                                }
                            })

                        # Handle different exit codes properly
                        if ($results.Success) {
                            if ($results.ExitCode -eq -1978335188) {
                                $message = "All application updates completed successfully in $($results.Duration).`n`nNote: Some updates completed with warnings, which is normal for WinGet operations."
                                Write-Logger "Application updates completed with normal WinGet warnings in $($results.Duration)" "SUCCESS"
                            }
                            else {
                                $message = "All application updates completed successfully in $($results.Duration)."
                                Write-Logger "Application updates completed successfully in $($results.Duration)" "SUCCESS"
                            }
                            $icon = [System.Windows.MessageBoxImage]::Information
                            $title = "WDCA - Updates Complete"
                        }
                        else {
                            $message = "Application updates completed with issues in $($results.Duration).`n`nExit Code: $($results.ExitCode)"
                            if ($results.Error) {
                                $message += "`n`nError: $($results.Error)"
                            }
                            $icon = [System.Windows.MessageBoxImage]::Warning
                            $title = "WDCA - Updates Completed with Issues"

                            Write-Logger "Application updates completed with issues: Exit Code $($results.ExitCode)" "WARNING"
                        }

                        # Safe MessageBox call with fallback handling
                        try {
                            [System.Windows.MessageBox]::Show($message, $title, [System.Windows.MessageBoxButton]::OK, $icon)
                        }
                        catch {
                            Write-Logger "MessageBox display failed, trying fallback: $($_.Exception.Message)" "WARNING"
                            try {
                                # Fallback without icon
                                [System.Windows.MessageBox]::Show($message, $title, [System.Windows.MessageBoxButton]::OK)
                            }
                            catch {
                                Write-Logger "All MessageBox attempts failed: $($_.Exception.Message)" "ERROR"
                                # Log the message instead
                                Write-Logger "Update Result: $message" "INFO"
                            }
                        }

                        Set-WDCAStatus "Ready - Updates completed"
                    }
                    catch {
                        Write-Logger "Error processing update results: $($_.Exception.Message)" "ERROR"

                        # Safe UI reset
                        try {
                            $global:sync.Form.Dispatcher.Invoke([action] {
                                    if ($global:sync.WPFUpdateApps) {
                                        $global:sync.WPFUpdateApps.Content = "Update All Apps"
                                        $global:sync.WPFUpdateApps.IsEnabled = $true
                                    }
                                    if ($global:sync.WPFProgressBar) {
                                        $global:sync.WPFProgressBar.Visibility = "Collapsed"
                                    }
                                })
                        }
                        catch {
                            Write-Logger "Failed to reset UI after error: $($_.Exception.Message)" "ERROR"
                        }

                        Set-WDCAStatus "Ready - Updates completed with errors"
                    }
                    finally {
                        Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue
                    }
                }
                elseif ($updateJob.State -eq 'Failed') {
                    $this.Stop()

                    Write-Logger "Update job failed" "ERROR"

                    $global:sync.Form.Dispatcher.Invoke([action] {
                            if ($global:sync.WPFUpdateApps) {
                                $global:sync.WPFUpdateApps.Content = "Update All Apps"
                                $global:sync.WPFUpdateApps.IsEnabled = $true
                            }
                            if ($global:sync.WPFProgressBar) {
                                $global:sync.WPFProgressBar.Visibility = "Collapsed"
                            }
                        })

                    # Safe MessageBox for error case
                    try {
                        [System.Windows.MessageBox]::Show(
                            "Application updates failed. Please try again or check your internet connection.",
                            "WDCA - Update Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }
                    catch {
                        Write-Logger "Failed to show error MessageBox: $($_.Exception.Message)" "ERROR"
                        Write-Logger "Update Error: Application updates failed. Please try again or check your internet connection." "ERROR"
                    }

                    Set-WDCAStatus "Ready - Updates failed"
                    Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Logger "Error in update timer: $($_.Exception.Message)" "ERROR"
                $this.Stop()
                Remove-Job -Job $updateJob -Force -ErrorAction SilentlyContinue

                # Emergency UI reset
                try {
                    $global:sync.Form.Dispatcher.Invoke([action] {
                            if ($global:sync.WPFUpdateApps) {
                                $global:sync.WPFUpdateApps.Content = "Update All Apps"
                                $global:sync.WPFUpdateApps.IsEnabled = $true
                            }
                            if ($global:sync.WPFProgressBar) {
                                $global:sync.WPFProgressBar.Visibility = "Collapsed"
                            }
                        })
                }
                catch {
                    Write-Logger "Emergency UI reset failed: $($_.Exception.Message)" "ERROR"
                }

                Set-WDCAStatus "Ready - Update process error"
            }
        }.GetNewClosure())

    $updateTimer.Start()
    Write-Logger "Background update job started" "INFO"
}
function Invoke-SystemDiagnosticsAsync {
    <#
    .SYNOPSIS
        Runs system diagnostic scans in correct dependency order: DISM → SFC → CHKDSK
    .DESCRIPTION
        Executes all diagnostic scans sequentially in a single terminal window.
        Follows best practice order: DISM repairs Windows image, then SFC checks system files, then CHKDSK checks disk.
    #>

    Write-Logger "Starting comprehensive system diagnostics (sequential execution)" "INFO"

    try {
        # Show initial confirmation dialog
        $result = [System.Windows.MessageBox]::Show(
            "This will run all system diagnostic scans in the correct order:`n`n" +
            "1. DISM - Repairs Windows image (foundation)`n" +
            "2. SFC - Checks system files (depends on DISM)`n" +
            "3. CHKDSK - Checks disk health (independent)`n`n" +
            "All scans will run sequentially in one terminal window.`n" +
            "Total estimated time: 20-60 minutes`n`n" +
            "Continue with sequential system diagnostics?",
            "WDCA - Sequential System Diagnostics",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($result -eq [System.Windows.MessageBoxResult]::No) {
            Write-Logger "Sequential system diagnostics cancelled by user" "INFO"
            return
        }

        Write-Logger "User confirmed: Starting sequential diagnostics in single window (DISM→SFC→CHKDSK)" "INFO"

        # Create combined script that runs all scans sequentially
        $tempScriptPath = Join-Path $env:TEMP "WDCA_Combined_Diagnostics.ps1"
        $logPath = Join-Path $env:TEMP "wdca_combined_diagnostics.log"
        $systemDrive = $env:SystemDrive

        $combinedScript = @"
# Terminal styling
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

# Combined logging function
function Write-DiagLog {
    param([string]`$Message, [string]`$Level = "INFO")
    try {
        `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path "$logPath" -Value "[`$timestamp] [`$Level] `$Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# Header
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "    WDCA Complete System Diagnostics Suite" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

Write-DiagLog "Combined diagnostics session started" "INFO"
Write-Host "[INFO] Running sequential system diagnostics: DISM -> SFC -> CHKDSK" -ForegroundColor Cyan
Write-Host "[INFO] Estimated total time: 20-60 minutes" -ForegroundColor Cyan
Write-Host ""

try {
    `$overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Step 1: DISM Operations
    Write-Host ("=" * 50) -ForegroundColor Yellow
    Write-Host "  Step 1/3: DISM Image Repair" -ForegroundColor Yellow
    Write-Host ("=" * 50) -ForegroundColor Yellow
    Write-DiagLog "Starting DISM operations" "INFO"

    # DISM CheckHealth
    Write-Host ""
    Write-Host "[DISM] Step 1a: Quick Health Check" -ForegroundColor Cyan
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DiagLog "Running: DISM /Online /Cleanup-Image /CheckHealth" "INFO"
    `$dismCheck = Start-Process -FilePath "dism.exe" -ArgumentList "/Online", "/Cleanup-Image", "/CheckHealth" -Wait -PassThru -NoNewWindow
    Write-Host "[DISM] CheckHealth completed (Exit: `$(`$dismCheck.ExitCode))" -ForegroundColor Gray

    # DISM ScanHealth
    Write-Host ""
    Write-Host "[DISM] Step 1b: Detailed Health Scan" -ForegroundColor Cyan
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DiagLog "Running: DISM /Online /Cleanup-Image /ScanHealth" "INFO"
    `$dismScan = Start-Process -FilePath "dism.exe" -ArgumentList "/Online", "/Cleanup-Image", "/ScanHealth" -Wait -PassThru -NoNewWindow
    Write-Host "[DISM] ScanHealth completed (Exit: `$(`$dismScan.ExitCode))" -ForegroundColor Gray

    # DISM RestoreHealth
    Write-Host ""
    Write-Host "[DISM] Step 1c: Image Repair" -ForegroundColor Cyan
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DiagLog "Running: DISM /Online /Cleanup-Image /RestoreHealth" "INFO"
    `$dismRestore = Start-Process -FilePath "dism.exe" -ArgumentList "/Online", "/Cleanup-Image", "/RestoreHealth" -Wait -PassThru -NoNewWindow
    Write-Host "[DISM] RestoreHealth completed (Exit: `$(`$dismRestore.ExitCode))" -ForegroundColor Gray

    Write-Host ""
    if (`$dismCheck.ExitCode -eq 0 -and `$dismScan.ExitCode -eq 0 -and `$dismRestore.ExitCode -eq 0) {
        Write-Host "[SUCCESS] DISM operations completed successfully" -ForegroundColor Green
        Write-DiagLog "DISM completed successfully" "SUCCESS"
    } else {
        Write-Host "[WARNING] DISM completed with some issues" -ForegroundColor Yellow
        Write-DiagLog "DISM completed with issues" "WARNING"
    }

    Write-Host ""
    Write-Host "Waiting 5 seconds before SFC..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5

    # Step 2: SFC Operation
    Write-Host ("=" * 50) -ForegroundColor Yellow
    Write-Host "  Step 2/3: SFC System File Check" -ForegroundColor Yellow
    Write-Host ("=" * 50) -ForegroundColor Yellow
    Write-DiagLog "Starting SFC scan" "INFO"

    Write-Host ""
    Write-Host "[SFC] Scanning system files..." -ForegroundColor Cyan
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DiagLog "Running: sfc.exe /scannow" "INFO"
    `$sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow

    Write-Host ""
    switch (`$sfcProcess.ExitCode) {
        0 {
            Write-Host "[SUCCESS] SFC completed - No issues found" -ForegroundColor Green
            Write-DiagLog "SFC completed successfully" "SUCCESS"
        }
        1 {
            Write-Host "[SUCCESS] SFC found and repaired files" -ForegroundColor Green
            Write-DiagLog "SFC found and repaired issues" "SUCCESS"
        }
        2 {
            Write-Host "[WARNING] SFC completed - Restart required" -ForegroundColor Yellow
            Write-DiagLog "SFC completed, restart required" "WARNING"
        }
        3 {
            Write-Host "[WARNING] SFC found unrepairable files" -ForegroundColor Yellow
            Write-DiagLog "SFC found unrepaired issues" "WARNING"
        }
        default {
            Write-Host "[WARNING] SFC completed with exit code `$(`$sfcProcess.ExitCode)" -ForegroundColor Yellow
            Write-DiagLog "SFC completed with exit code `$(`$sfcProcess.ExitCode)" "WARNING"
        }
    }

    Write-Host ""
    Write-Host "Waiting 5 seconds before CHKDSK..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5

    # Step 3: CHKDSK Operation
    Write-Host ("=" * 50) -ForegroundColor Yellow
    Write-Host "  Step 3/3: CHKDSK Disk Check" -ForegroundColor Yellow
    Write-Host ("=" * 50) -ForegroundColor Yellow
    Write-DiagLog "Starting CHKDSK scan on drive $systemDrive" "INFO"

    Write-Host ""
    Write-Host "[CHKDSK] Checking disk: $systemDrive" -ForegroundColor Cyan
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DiagLog "Running: chkdsk $systemDrive /f /r" "INFO"
    `$chkdskProcess = Start-Process -FilePath "chkdsk.exe" -ArgumentList "$systemDrive", "/f", "/r" -Wait -PassThru -NoNewWindow

    Write-Host ""
    switch (`$chkdskProcess.ExitCode) {
        0 {
            Write-Host "[SUCCESS] CHKDSK completed - No errors found" -ForegroundColor Green
            Write-DiagLog "CHKDSK completed successfully" "SUCCESS"
        }
        1 {
            Write-Host "[SUCCESS] CHKDSK found and fixed errors" -ForegroundColor Green
            Write-DiagLog "CHKDSK found and fixed errors" "SUCCESS"
        }
        2 {
            Write-Host "[SCHEDULED] CHKDSK scheduled for next reboot" -ForegroundColor Yellow
            Write-Host "  System drive is in use - restart required" -ForegroundColor Yellow
            Write-DiagLog "CHKDSK scheduled for next reboot" "INFO"
        }
        default {
            Write-Host "[WARNING] CHKDSK completed with exit code `$(`$chkdskProcess.ExitCode)" -ForegroundColor Yellow
            Write-DiagLog "CHKDSK completed with exit code `$(`$chkdskProcess.ExitCode)" "WARNING"
        }
    }

    `$overallStopwatch.Stop()

    # Final Summary
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "    DIAGNOSTICS COMPLETE" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Summary of Results:" -ForegroundColor Yellow
    Write-Host "  DISM CheckHealth:   Exit Code `$(`$dismCheck.ExitCode)" -ForegroundColor Gray
    Write-Host "  DISM ScanHealth:    Exit Code `$(`$dismScan.ExitCode)" -ForegroundColor Gray
    Write-Host "  DISM RestoreHealth: Exit Code `$(`$dismRestore.ExitCode)" -ForegroundColor Gray
    Write-Host "  SFC Scan:           Exit Code `$(`$sfcProcess.ExitCode)" -ForegroundColor Gray
    Write-Host "  CHKDSK Scan:        Exit Code `$(`$chkdskProcess.ExitCode)" -ForegroundColor Gray
    Write-Host "  Total Duration:     `$(`$overallStopwatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Gray

    Write-Host ""
    # Overall system health assessment
    `$allGood = (`$dismCheck.ExitCode -eq 0 -and `$dismScan.ExitCode -eq 0 -and `$dismRestore.ExitCode -eq 0 -and `$sfcProcess.ExitCode -le 1 -and `$chkdskProcess.ExitCode -le 1)
    if (`$allGood) {
        Write-Host "Overall Status: SYSTEM HEALTHY" -ForegroundColor Green
        Write-DiagLog "All diagnostics completed successfully - system healthy" "SUCCESS"
    } else {
        Write-Host "Overall Status: ATTENTION REQUIRED" -ForegroundColor Yellow
        Write-DiagLog "Some diagnostics completed with issues" "WARNING"

        if (`$chkdskProcess.ExitCode -eq 2) {
            Write-Host "Action Required: Restart computer to complete CHKDSK" -ForegroundColor Cyan
        }
    }

}
catch {
    Write-Host "[ERROR] Critical error during diagnostics: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-DiagLog "Critical error: `$(`$_.Exception.Message)" "ERROR"
}

# Footer
Write-Host ""
Write-Host ("-" * 60) -ForegroundColor DarkGray
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
Write-DiagLog "Combined diagnostics session completed" "INFO"

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

        # Create and run the combined script
        Set-Content -Path $tempScriptPath -Value $combinedScript -Encoding UTF8
        Write-Logger "Created combined diagnostics script: $tempScriptPath" "INFO"

        $combinedProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started combined diagnostics terminal (PID: $($combinedProcess.Id))" "SUCCESS"

        # Cleanup script after use
        Start-Job -ScriptBlock {
            param($ProcessId, $ScriptPath)
            try {
                $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                if ($process) { $process.WaitForExit() }
                Start-Sleep -Seconds 5
                if (Test-Path $ScriptPath) {
                    Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        } -ArgumentList $combinedProcess.Id, $tempScriptPath | Out-Null

        # Show immediate completion message
        [System.Windows.MessageBox]::Show(
            "Sequential system diagnostics started!`n`n" +
            "All scans (DISM → SFC → CHKDSK) will run in one terminal window.`n`n" +
            "Log file: $logPath",
            "WDCA - Diagnostics Started",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )

    }
    catch {
        Write-Logger "Critical error in sequential diagnostics: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "A critical error occurred starting diagnostics:`n$($_.Exception.Message)",
            "WDCA - Critical Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
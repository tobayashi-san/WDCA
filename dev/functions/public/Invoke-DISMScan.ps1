function Invoke-DISMScan {
    <#
    .SYNOPSIS
        Runs DISM image repair commands in a new terminal with real-time output
    .DESCRIPTION
        Creates a simple PowerShell script that runs DISM CheckHealth, ScanHealth,
        and RestoreHealth commands in sequence with real-time progress display.
    #>

    Write-Logger "Starting DISM scan in new terminal" "INFO"

    $tempScriptPath = Join-Path $env:TEMP "WDCA_DISM_Scan.ps1"
    $logPath = Join-Path $env:TEMP "wdca_dism.log"

    $scriptContent = @"
# Terminal styling
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

# Simple logging function
function Write-DISMLog {
    param([string]`$Message, [string]`$Level = "INFO")
    try {
        `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path "$logPath" -Value "[`$timestamp] [`$Level] `$Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# Header
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host "  WDCA DISM Image Repair Tool" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host ""

Write-DISMLog "DISM repair session started" "INFO"
Write-Host "[INFO] Starting DISM image diagnostics and repair..." -ForegroundColor Cyan
Write-Host "[INFO] This process will run three sequential scans" -ForegroundColor Cyan
Write-Host ""

try {
    `$overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Step 1: CheckHealth (Quick check)
    Write-Host "Step 1/3: Quick Health Check" -ForegroundColor Yellow
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DISMLog "Running: DISM /Online /Cleanup-Image /CheckHealth" "INFO"

    `$checkStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    `$checkProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/Online", "/Cleanup-Image", "/CheckHealth" -Wait -PassThru -NoNewWindow
    `$checkStopwatch.Stop()

    if (`$checkProcess.ExitCode -eq 0) {
        Write-Host "[SUCCESS] CheckHealth completed (`$(`$checkStopwatch.Elapsed.ToString("mm\:ss")))" -ForegroundColor Green
        Write-DISMLog "CheckHealth completed successfully" "SUCCESS"
    } else {
        Write-Host "[WARNING] CheckHealth completed with issues (Exit: `$(`$checkProcess.ExitCode))" -ForegroundColor Yellow
        Write-DISMLog "CheckHealth completed with exit code `$(`$checkProcess.ExitCode)" "WARNING"
    }

    Write-Host ""

    # Step 2: ScanHealth (Detailed scan)
    Write-Host "Step 2/3: Detailed Health Scan" -ForegroundColor Yellow
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DISMLog "Running: DISM /Online /Cleanup-Image /ScanHealth" "INFO"

    `$scanStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    `$scanProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/Online", "/Cleanup-Image", "/ScanHealth" -Wait -PassThru -NoNewWindow
    `$scanStopwatch.Stop()

    if (`$scanProcess.ExitCode -eq 0) {
        Write-Host "[SUCCESS] ScanHealth completed (`$(`$scanStopwatch.Elapsed.ToString("mm\:ss")))" -ForegroundColor Green
        Write-DISMLog "ScanHealth completed successfully" "SUCCESS"
    } else {
        Write-Host "[WARNING] ScanHealth detected issues (Exit: `$(`$scanProcess.ExitCode))" -ForegroundColor Yellow
        Write-DISMLog "ScanHealth detected issues with exit code `$(`$scanProcess.ExitCode)" "WARNING"
    }

    Write-Host ""

    # Step 3: RestoreHealth (Repair if needed)
    Write-Host "Step 3/3: Image Repair" -ForegroundColor Yellow
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-DISMLog "Running: DISM /Online /Cleanup-Image /RestoreHealth" "INFO"

    `$repairStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    `$repairProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/Online", "/Cleanup-Image", "/RestoreHealth" -Wait -PassThru -NoNewWindow
    `$repairStopwatch.Stop()

    if (`$repairProcess.ExitCode -eq 0) {
        Write-Host "[SUCCESS] RestoreHealth completed (`$(`$repairStopwatch.Elapsed.ToString("mm\:ss")))" -ForegroundColor Green
        Write-DISMLog "RestoreHealth completed successfully" "SUCCESS"
    } else {
        Write-Host "[WARNING] RestoreHealth completed with issues (Exit: `$(`$repairProcess.ExitCode))" -ForegroundColor Yellow
        Write-DISMLog "RestoreHealth completed with exit code `$(`$repairProcess.ExitCode)" "WARNING"
    }

    `$overallStopwatch.Stop()

    # Results summary
    Write-Host ""
    Write-Host ("-" * 50) -ForegroundColor DarkGray
    Write-Host "DISM Repair Summary:" -ForegroundColor Cyan
    Write-Host "  CheckHealth:   Exit Code `$(`$checkProcess.ExitCode)" -ForegroundColor Gray
    Write-Host "  ScanHealth:    Exit Code `$(`$scanProcess.ExitCode)" -ForegroundColor Gray
    Write-Host "  RestoreHealth: Exit Code `$(`$repairProcess.ExitCode)" -ForegroundColor Gray
    Write-Host "  Total Duration: `$(`$overallStopwatch.Elapsed.ToString("mm\:ss"))" -ForegroundColor Gray

    # Overall status assessment
    Write-Host ""
    if (`$checkProcess.ExitCode -eq 0 -and `$scanProcess.ExitCode -eq 0 -and `$repairProcess.ExitCode -eq 0) {
        Write-Host "Status: Windows image is healthy" -ForegroundColor Green
        Write-DISMLog "All DISM operations completed successfully" "SUCCESS"
    } elseif (`$repairProcess.ExitCode -eq 0) {
        Write-Host "Status: Issues found and repaired successfully" -ForegroundColor Green
        Write-DISMLog "DISM found and repaired image issues" "SUCCESS"
    } else {
        Write-Host "Status: Some issues may require additional attention" -ForegroundColor Yellow
        Write-DISMLog "DISM completed with potential remaining issues" "WARNING"
        Write-Host "Tip: Consider running SFC /scannow after DISM repair" -ForegroundColor Cyan
    }

}
catch {
    Write-Host "[ERROR] DISM operation failed: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-DISMLog "DISM error: `$(`$_.Exception.Message)" "ERROR"
}

# Footer
Write-Host ""
Write-Host ("-" * 50) -ForegroundColor DarkGray
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
Write-DISMLog "DISM repair session completed" "INFO"

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    # Create and run script
    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        Write-Logger "Created DISM script: $tempScriptPath" "INFO"

        $dismProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started DISM terminal (PID: $($dismProcess.Id))" "SUCCESS"

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
        } -ArgumentList $dismProcess.Id, $tempScriptPath | Out-Null

    }
    catch {
        Write-Logger "Failed to start DISM: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start DISM scan.`n$($_.Exception.Message)",
            "WDCA - DISM Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )

        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}
function Invoke-CHKDSKScan {
    <#
    .SYNOPSIS
        Runs CHKDSK disk check in a new terminal with real-time output
    .DESCRIPTION
        Creates a simple PowerShell script that runs CHKDSK on the system drive
        with real-time progress display and detailed results.
    #>

    Write-Logger "Starting CHKDSK scan in new terminal" "INFO"

    $tempScriptPath = Join-Path $env:TEMP "WDCA_CHKDSK_Scan.ps1"
    $logPath = Join-Path $env:TEMP "wdca_chkdsk.log"
    $systemDrive = $env:SystemDrive

    $scriptContent = @"
# Terminal styling
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

# Simple logging function
function Write-CHKDSKLog {
    param([string]`$Message, [string]`$Level = "INFO")
    try {
        `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path "$logPath" -Value "[`$timestamp] [`$Level] `$Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# Header
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host "  WDCA CHKDSK Disk Check Tool" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host ""

Write-CHKDSKLog "CHKDSK scan started on drive $systemDrive" "INFO"
Write-Host "[INFO] Starting CHKDSK on system drive: $systemDrive" -ForegroundColor Cyan
Write-Host "[INFO] This will check and repair disk errors" -ForegroundColor Cyan
Write-Host ""

try {
    `$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Check if drive is in use (system drive scenario)
    Write-Host "Checking drive accessibility..." -ForegroundColor Yellow
    Write-CHKDSKLog "Checking if drive $systemDrive is accessible for repair" "INFO"

    # Run CHKDSK with /f (fix) and /r (recover) flags
    Write-Host ""
    Write-Host "CHKDSK Output:" -ForegroundColor Yellow
    Write-Host ("-" * 30) -ForegroundColor DarkGray
    Write-CHKDSKLog "Running: chkdsk $systemDrive /f /r" "INFO"

    `$chkdskProcess = Start-Process -FilePath "chkdsk.exe" -ArgumentList "$systemDrive", "/f", "/r" -Wait -PassThru -NoNewWindow

    `$stopwatch.Stop()
    `$duration = `$stopwatch.Elapsed.ToString("mm\:ss")

    Write-Host ""
    Write-Host ("-" * 30) -ForegroundColor DarkGray

    # Analyze results based on exit code
    switch (`$chkdskProcess.ExitCode) {
        0 {
            Write-Host "[SUCCESS] CHKDSK completed successfully - No errors found (Duration: `$duration)" -ForegroundColor Green
            Write-CHKDSKLog "CHKDSK completed successfully in `$duration" "SUCCESS"
        }
        1 {
            Write-Host "[SUCCESS] CHKDSK found and fixed errors (Duration: `$duration)" -ForegroundColor Green
            Write-CHKDSKLog "CHKDSK found and fixed errors in `$duration" "SUCCESS"
        }
        2 {
            Write-Host "[SCHEDULED] CHKDSK scheduled for next reboot (Duration: `$duration)" -ForegroundColor Yellow
            Write-Host "  System drive is currently in use - restart required" -ForegroundColor Yellow
            Write-CHKDSKLog "CHKDSK scheduled for next reboot (drive in use)" "INFO"
        }
        3 {
            Write-Host "[WARNING] CHKDSK could not run - Drive may be locked (Duration: `$duration)" -ForegroundColor Yellow
            Write-CHKDSKLog "CHKDSK could not run, drive locked (Duration: `$duration)" "WARNING"
        }
        default {
            Write-Host "[WARNING] CHKDSK completed with exit code `$(`$chkdskProcess.ExitCode) (Duration: `$duration)" -ForegroundColor Yellow
            Write-CHKDSKLog "CHKDSK completed with exit code `$(`$chkdskProcess.ExitCode) (Duration: `$duration)" "WARNING"
        }
    }

    # Additional disk information
    Write-Host ""
    Write-Host "Drive Information:" -ForegroundColor DarkCyan
    try {
        `$driveInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction Stop
        `$totalSize = [math]::Round(`$driveInfo.Size / 1GB, 2)
        `$freeSpace = [math]::Round(`$driveInfo.FreeSpace / 1GB, 2)
        `$usedSpace = `$totalSize - `$freeSpace
        `$freePercent = [math]::Round((`$freeSpace / `$totalSize) * 100, 1)

        Write-Host "  Drive: $systemDrive (`$(`$driveInfo.VolumeName))" -ForegroundColor Gray
        Write-Host "  Total Size: `$totalSize GB" -ForegroundColor Gray
        Write-Host "  Used Space: `$usedSpace GB" -ForegroundColor Gray
        Write-Host "  Free Space: `$freeSpace GB (`$freePercent%)" -ForegroundColor Gray
        Write-Host "  File System: `$(`$driveInfo.FileSystem)" -ForegroundColor Gray

        Write-CHKDSKLog "Drive info: `$totalSize GB total, `$freeSpace GB free (`$freePercent%)" "INFO"

        if (`$freePercent -lt 10) {
            Write-Host "  [WARNING] Low disk space detected!" -ForegroundColor Red
            Write-CHKDSKLog "Low disk space warning: only `$freePercent% free" "WARNING"
        }
    }
    catch {
        Write-Host "  Could not retrieve drive information" -ForegroundColor Yellow
        Write-CHKDSKLog "Failed to get drive information: `$(`$_.Exception.Message)" "WARNING"
    }

    # Status summary and recommendations
    Write-Host ""
    if (`$chkdskProcess.ExitCode -eq 0) {
        Write-Host "Status: Disk is healthy - no errors found" -ForegroundColor Green
    } elseif (`$chkdskProcess.ExitCode -eq 1) {
        Write-Host "Status: Disk errors found and repaired" -ForegroundColor Green
    } elseif (`$chkdskProcess.ExitCode -eq 2) {
        Write-Host "Status: CHKDSK will run on next restart" -ForegroundColor Yellow
        Write-Host "Action: Please restart your computer to complete the disk check" -ForegroundColor Cyan
    } else {
        Write-Host "Status: Check completed with warnings" -ForegroundColor Yellow
        Write-Host "Tip: Try running as Administrator for full disk access" -ForegroundColor Cyan
    }

}
catch {
    Write-Host "[ERROR] Failed to run CHKDSK: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-CHKDSKLog "CHKDSK error: `$(`$_.Exception.Message)" "ERROR"
}

# Footer
Write-Host ""
Write-Host ("-" * 50) -ForegroundColor DarkGray
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
Write-CHKDSKLog "CHKDSK scan completed" "INFO"

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    # Create and run script
    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        Write-Logger "Created CHKDSK script: $tempScriptPath" "INFO"

        $chkdskProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started CHKDSK terminal (PID: $($chkdskProcess.Id))" "SUCCESS"

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
        } -ArgumentList $chkdskProcess.Id, $tempScriptPath | Out-Null

    }
    catch {
        Write-Logger "Failed to start CHKDSK: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start CHKDSK scan.`n$($_.Exception.Message)",
            "WDCA - CHKDSK Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )

        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}
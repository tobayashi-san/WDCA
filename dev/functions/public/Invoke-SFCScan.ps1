function Invoke-SFCScan {
    <#
    .SYNOPSIS
        Runs System File Checker (SFC) in a new terminal with real-time output
    .DESCRIPTION
        Creates a simple PowerShell script that runs SFC scan in a new terminal window
        and displays real-time progress and results.
    #>

    Write-Logger "Starting SFC scan in new terminal" "INFO"

    $tempScriptPath = Join-Path $env:TEMP "WDCA_SFC_Scan.ps1"
    $logPath = Join-Path $env:TEMP "wdca_sfc.log"

    $scriptContent = @"
# Terminal styling
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

# Simple logging function
function Write-SFCLog {
    param([string]`$Message, [string]`$Level = "INFO")
    try {
        `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path "$logPath" -Value "[`$timestamp] [`$Level] `$Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# Header
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host "  WDCA System File Checker (SFC)" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan
Write-Host ""

Write-SFCLog "SFC scan started" "INFO"
Write-Host "[INFO] Starting System File Checker scan..." -ForegroundColor Cyan
Write-Host "[INFO] This may take several minutes - please wait" -ForegroundColor Cyan
Write-Host ""

try {
    `$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Run SFC with real-time output
    Write-Host "SFC Output:" -ForegroundColor Yellow
    Write-Host ("-" * 30) -ForegroundColor DarkGray

    `$sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow

    `$stopwatch.Stop()
    `$duration = `$stopwatch.Elapsed.ToString("mm\:ss")

    Write-Host ""
    Write-Host ("-" * 30) -ForegroundColor DarkGray

    # Show results based on exit code
    switch (`$sfcProcess.ExitCode) {
        0 {
            Write-Host "[SUCCESS] SFC completed - No issues found (Duration: `$duration)" -ForegroundColor Green
            Write-SFCLog "SFC completed successfully in `$duration" "SUCCESS"
        }
        1 {
            Write-Host "[SUCCESS] SFC completed - Found and repaired files (Duration: `$duration)" -ForegroundColor Green
            Write-SFCLog "SFC found and repaired issues in `$duration" "SUCCESS"
        }
        2 {
            Write-Host "[WARNING] SFC completed - Restart required (Duration: `$duration)" -ForegroundColor Yellow
            Write-SFCLog "SFC completed, restart required (Duration: `$duration)" "WARNING"
        }
        3 {
            Write-Host "[WARNING] SFC completed - Some files could not be repaired (Duration: `$duration)" -ForegroundColor Yellow
            Write-SFCLog "SFC found unrepaired issues (Duration: `$duration)" "WARNING"
        }
        default {
            Write-Host "[WARNING] SFC completed with exit code `$(`$sfcProcess.ExitCode) (Duration: `$duration)" -ForegroundColor Yellow
            Write-SFCLog "SFC completed with exit code `$(`$sfcProcess.ExitCode) (Duration: `$duration)" "WARNING"
        }
    }

    # Show recent CBS.log entries if available
    `$cbsLogPath = Join-Path `$env:SystemRoot "Logs\CBS\CBS.log"
    if (Test-Path `$cbsLogPath) {
        Write-Host ""
        Write-Host "Recent CBS.log entries:" -ForegroundColor DarkCyan
        try {
            Get-Content `$cbsLogPath -Tail 10 -ErrorAction Stop | ForEach-Object {
                if (`$_ -match "error|failed|corrupt") {
                    Write-Host "  `$_" -ForegroundColor Red
                } elseif (`$_ -match "repaired|success") {
                    Write-Host "  `$_" -ForegroundColor Green
                } else {
                    Write-Host "  `$_" -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Host "  Could not read CBS.log" -ForegroundColor Yellow
        }
    }

    # Simple status summary
    Write-Host ""
    if (`$sfcProcess.ExitCode -eq 0) {
        Write-Host "Status: System files are healthy" -ForegroundColor Green
    } elseif (`$sfcProcess.ExitCode -eq 1) {
        Write-Host "Status: Issues found and repaired" -ForegroundColor Green
    } elseif (`$sfcProcess.ExitCode -eq 2) {
        Write-Host "Status: Restart required to complete repairs" -ForegroundColor Yellow
    } elseif (`$sfcProcess.ExitCode -eq 3) {
        Write-Host "Status: Some issues require manual attention" -ForegroundColor Yellow
        Write-Host "Tip: Try running DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Cyan
    }

}
catch {
    Write-Host "[ERROR] Failed to run SFC: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-SFCLog "SFC error: `$(`$_.Exception.Message)" "ERROR"
}

# Footer
Write-Host ""
Write-Host ("-" * 50) -ForegroundColor DarkGray
Write-Host "Log saved to: $logPath" -ForegroundColor Cyan
Write-SFCLog "SFC scan completed" "INFO"

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    # Create and run script
    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        Write-Logger "Created SFC script: $tempScriptPath" "INFO"

        $sfcProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started SFC terminal (PID: $($sfcProcess.Id))" "SUCCESS"

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
        } -ArgumentList $sfcProcess.Id, $tempScriptPath | Out-Null

    }
    catch {
        Write-Logger "Failed to start SFC: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start SFC scan.`n$($_.Exception.Message)",
            "WDCA - SFC Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )

        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}
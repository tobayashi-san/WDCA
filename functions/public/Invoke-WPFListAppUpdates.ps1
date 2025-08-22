function Invoke-WPFListAppUpdates {
    <#
    .SYNOPSIS
        Lists available application updates in a new terminal window
    #>

    Write-Logger "Starting application update check in new terminal" "INFO"

    $tempScriptPath = Join-Path $env:TEMP "WDCA_AppUpdate_Check.ps1"
    $logPath = Join-Path $env:TEMP "wdca_app_updates.log"

    $scriptContent = @"
# Terminal styling
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

# Header
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  WDCA Application Update Scanner" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Scanning for available application updates..." -ForegroundColor Cyan
Write-Host ""

try {
    # Run winget upgrade
    Write-Host "[INFO] Running: winget upgrade --include-unknown" -ForegroundColor Cyan
    `$wingetOutput = winget upgrade --include-unknown 2>&1

    if (`$wingetOutput) {
        Write-Host "[SUCCESS] Scan completed" -ForegroundColor Green
        Write-Host ""

        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "  WINGET OUTPUT" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""

        # Show the output with better formatting
        `$updateCount = 0
        `$apps = @()

        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host "  AVAILABLE UPDATES" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Cyan
        Write-Host ""

        foreach (`$line in `$wingetOutput) {
            # Update entries (in table and containing version numbers)
            if (`$line -match "^[A-Z].*[\d\.].*[\d\.].*winget" -and `$line -notmatch "Name.*Version") {
                `$updateCount++
                # Extract app name and ID for examples
                if (`$line -match "(\S+\.\S+)") {
                    `$apps += `$matches[1]
                }
                Write-Host "[`$updateCount] `$line" -ForegroundColor Green
            }
            # Explicit targeting section
            elseif (`$line -match "^[A-Za-z].*Discord|^Discord") {
                `$updateCount++
                `$apps += "Discord.Discord"
                Write-Host "[`$updateCount] `$line (requires --id)" -ForegroundColor Yellow
            }
        }

        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "  SUMMARY" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host ""

        if (`$updateCount -gt 0) {
            Write-Host "Found `$updateCount application(s) ready to update" -ForegroundColor Green
        } else {
            Write-Host "All applications are up to date" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Yellow
        Write-Host "  QUICK ACTIONS" -ForegroundColor Yellow
        Write-Host ("=" * 60) -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Update all:        winget upgrade --all" -ForegroundColor Cyan
        Write-Host "Update silently:   winget upgrade --all --silent" -ForegroundColor Cyan
        Write-Host ""

        if (`$apps.Count -gt 0) {
            Write-Host "Update examples:" -ForegroundColor White
            `$examples = `$apps | Select-Object -First 2
            foreach (`$app in `$examples) {
                Write-Host "  winget upgrade --id `$app" -ForegroundColor Cyan
            }
        }

        Write-Host ""
        Write-Host "Tip: Run as Administrator for best results" -ForegroundColor DarkYellow
    }
    else {
        Write-Host "[ERROR] No output from WinGet" -ForegroundColor Red
    }
}
catch {
    Write-Host "[ERROR] Failed to run WinGet: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    # Create and run script
    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        Write-Logger "Created app update check script: $tempScriptPath" "INFO"

        $updateProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started app update check terminal (PID: $($updateProcess.Id))" "SUCCESS"

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
        } -ArgumentList $updateProcess.Id, $tempScriptPath | Out-Null

    }
    catch {
        Write-Logger "Failed to start app update check: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start application update check.`n$($_.Exception.Message)",
            "WDCA - Update Check Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )

        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}

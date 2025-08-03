function Invoke-WPFUpdateApps {
    <#
    .SYNOPSIS
        Updates all available applications in a new terminal window
    #>

    Write-Logger "Starting application updates in new terminal" "INFO"

    # Show confirmation dialog
    $confirmResult = [System.Windows.MessageBox]::Show(
        "This will update all applications using WinGet.`n`n" +
        "Continue with application updates?",
        "WDCA - Confirm Application Updates",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Application updates cancelled by user" "INFO"
        return
    }

    $tempScriptPath = Join-Path $env:TEMP "WDCA_AppUpdate_Install.ps1"

    $scriptContent = @"
# Terminal styling
`$Host.UI.RawUI.BackgroundColor = "Black"
`$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

# Header
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  WDCA Application Update Installer" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Starting application update process..." -ForegroundColor Cyan
Write-Host ""

try {
    # Check WinGet
    Write-Host "[INFO] Checking WinGet availability..." -ForegroundColor Cyan
    `$wingetVersion = winget --version
    Write-Host "[SUCCESS] WinGet available - Version: `$wingetVersion" -ForegroundColor Green
    Write-Host ""

    # Run the update
    Write-Host "[INFO] Running: winget upgrade --all --silent --accept-source-agreements --accept-package-agreements" -ForegroundColor Cyan
    Write-Host ""

    `$startTime = Get-Date

    # Execute the upgrade command and show output in real-time
    winget upgrade --all --silent --accept-source-agreements --accept-package-agreements

    `$endTime = Get-Date
    `$duration = (`$endTime - `$startTime).ToString("mm\:ss")

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "  UPDATE PROCESS COMPLETED" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""
    Write-Host "[SUMMARY] Update process completed in `$duration" -ForegroundColor Cyan
    Write-Host "[SUMMARY] Check output above for individual app results" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[RECOMMENDATION] Restart applications to use new versions" -ForegroundColor Yellow
    Write-Host "[RECOMMENDATION] Consider restarting Windows if system components were updated" -ForegroundColor Yellow

}
catch {
    Write-Host "[ERROR] Update process failed: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Blue
`$null = `$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

    # Create and run script
    try {
        Set-Content -Path $tempScriptPath -Value $scriptContent -Encoding UTF8
        Write-Logger "Created app update install script: $tempScriptPath" "INFO"

        $updateProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$tempScriptPath`""
        ) -WindowStyle Normal -PassThru

        Write-Logger "Started app update install terminal (PID: $($updateProcess.Id))" "SUCCESS"

        # Show immediate confirmation
        [System.Windows.MessageBox]::Show(
            "Application update process started!`n`n" +
            "Updates will be installed in the new terminal window.",
            "WDCA - Updates Started",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )

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
        Write-Logger "Failed to start app updates: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start application updates.`n$($_.Exception.Message)",
            "WDCA - Update Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )

        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}
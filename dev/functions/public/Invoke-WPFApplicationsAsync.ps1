# Antivirus-freundliche WinGet Installation fÃ¼r WDCA
# Ersetzt die aktuelle Invoke-WPFApplicationsAsync.ps1 Funktion

function Invoke-WPFApplicationsAsync {
    <#
    .SYNOPSIS
        Antivirus-freundliche WinGet Installation mit transparenten Prozessen
    #>

    Write-Logger "Starting antivirus-friendly WinGet installation" "INFO"

    # AusgewÃ¤hlte Apps sammeln (unverÃ¤ndert)
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

    # BestÃ¤tigung mit detaillierter App-Liste
    $appList = ($selectedApps | ForEach-Object { "â€¢ $($_.DisplayName)" }) -join "`n"
    $confirmResult = [System.Windows.MessageBox]::Show(
        "Install $($selectedApps.Count) selected applications?`n`n$appList`n`nInstallation will start in a new command prompt window.",
        "WDCA - Confirm Installation",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Application installation cancelled by user" "INFO"
        return
    }

    # WinGet VerfÃ¼gbarkeitstest mit transparenter Ausgabe
    try {
        Write-Logger "Testing WinGet availability..." "INFO"
        $wingetVersion = & winget --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet exit code: $LASTEXITCODE"
        }
        Write-Logger "WinGet test successful: $wingetVersion" "INFO"
    }
    catch {
        Write-Logger "WinGet test failed: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "WinGet is not working properly. Please ensure WinGet is installed and accessible.`n`nError: $($_.Exception.Message)",
            "WDCA - WinGet Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    # ANTIVIRUS-FREUNDLICH: Transparente CMD-LÃ¶sung statt verstecktes PowerShell
    $batchScriptPath = Join-Path $env:TEMP "WDCA_WinGet_Install.cmd"
    $logPath = Join-Path $env:TEMP "wdca_winget_install.log"

    # Batch-Script erstellen (weniger verdÃ¤chtig fÃ¼r AV)
    $batchContent = @"
@echo off
title WDCA WinGet Installation
color 0F
echo ============================================================
echo Windows Deployment and Configuration Assistant
echo WinGet Application Installation
echo ============================================================
echo.
echo Installing $($selectedApps.Count) applications...
echo Log file: $logPath
echo.

REM Log start
echo [%DATE% %TIME%] WDCA WinGet installation started >> "$logPath"
echo [%DATE% %TIME%] Applications to install: $($selectedApps.Count) >> "$logPath"

"@

    # FÃ¼r jede App einen separaten WinGet-Aufruf hinzufÃ¼gen
    foreach ($app in $selectedApps) {
        $batchContent += @"

echo Installing: $($app.DisplayName)...
echo [%DATE% %TIME%] Installing: $($app.DisplayName) (ID: $($app.WingetId)) >> "$logPath"

REM Standard WinGet installation command
winget install --id "$($app.WingetId)" --silent --accept-source-agreements --accept-package-agreements --force

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] $($app.DisplayName) installed successfully
    echo [%DATE% %TIME%] SUCCESS: $($app.DisplayName) >> "$logPath"
) else (
    echo [ERROR] $($app.DisplayName) installation failed ^(Exit Code: %ERRORLEVEL%^)
    echo [%DATE% %TIME%] ERROR: $($app.DisplayName) - Exit Code: %ERRORLEVEL% >> "$logPath"
)
echo.

"@
    }

    # Batch-Script Abschluss
    $batchContent += @"

echo ============================================================
echo Installation completed
echo [%DATE% %TIME%] WDCA WinGet installation completed >> "$logPath"
echo.
echo Log file saved to: $logPath
echo.
echo Press any key to close this window...
pause >nul

"@

    try {
        # Batch-Datei erstellen
        Set-Content -Path $batchScriptPath -Value $batchContent -Encoding ASCII
        Write-Logger "Created batch installation script: $batchScriptPath" "INFO"

        # TRANSPARENTER START: Verwende CMD statt PowerShell
        $startProcessArgs = @{
            FilePath = "cmd.exe"
            ArgumentList = @("/c", "`"$batchScriptPath`"")
            WindowStyle = "Normal"
            PassThru = $true
        }

        $installProcess = Start-Process @startProcessArgs
        Write-Logger "Started installation via CMD (PID: $($installProcess.Id))" "SUCCESS"

        # Cleanup-Job fÃ¼r Batch-Datei
        Start-Job -ScriptBlock {
            param($ProcessId, $BatchPath)
            try {
                # Warten bis Prozess beendet ist
                $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                if ($process) {
                    $process.WaitForExit()
                }

                # Kurz warten und dann aufrÃ¤umen
                Start-Sleep -Seconds 5

                if (Test-Path $BatchPath) {
                    Remove-Item $BatchPath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Stille Behandlung von Cleanup-Fehlern
            }
        } -ArgumentList $installProcess.Id, $batchScriptPath | Out-Null

        # Erfolgs-Nachricht
        [System.Windows.MessageBox]::Show(
            "Application installation started!`n`nMonitor progress in the command prompt window.`n`nLog file: $logPath",
            "WDCA - Installation Started",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )

    }
    catch {
        Write-Logger "Error starting installation: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start installation:`n$($_.Exception.Message)",
            "WDCA - Installation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )

        # AufrÃ¤umen bei Fehler
        if (Test-Path $batchScriptPath) {
            Remove-Item $batchScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Alternative Methode: Direkte WinGet-Aufrufe ohne Script-Dateien
function Invoke-WPFApplicationsDirectCall {
    <#
    .SYNOPSIS
        Alternative: Direkte WinGet-Aufrufe ohne temporÃ¤re Dateien
    #>

    # ... (App-Sammlung wie oben) ...

    try {
        foreach ($app in $selectedApps) {
            Write-Logger "Installing: $($app.DisplayName)" "INFO"

            # Direkter WinGet-Aufruf ohne temporÃ¤re Dateien
            $wingetArgs = @(
                "install",
                "--id", $app.WingetId,
                "--silent",
                "--accept-source-agreements",
                "--accept-package-agreements",
                "--force"
            )

            # Sichtbarer Prozess starten
            $installProcess = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow

            if ($installProcess.ExitCode -eq 0) {
                Write-Logger "Successfully installed: $($app.DisplayName)" "SUCCESS"
            } else {
                Write-Logger "Failed to install: $($app.DisplayName) (Exit: $($installProcess.ExitCode))" "ERROR"
            }
        }

        [System.Windows.MessageBox]::Show(
            "Installation completed!`n`nCheck the WDCA log for detailed results.",
            "WDCA - Installation Complete",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
    }
    catch {
        Write-Logger "Error during direct installation: $($_.Exception.Message)" "ERROR"
    }
}

# Antivirus-Whitelist Hilfsfunktionen
function New-AVExclusionRequest {
    <#
    .SYNOPSIS
        Generiert Informationen fÃ¼r Antivirus-Ausnahmen
    #>

    $exclusionInfo = @"
WDCA Antivirus Exclusion Request
================================

Application: Windows Deployment & Configuration Assistant (WDCA)
Version: 25.01.01
Publisher: Tobayashi-san
License: MIT License
Repository: https://github.com/Tobayashi-san/WDCA

EXCLUDED PATHS:
- $($global:sync.PSScriptRoot)
- $env:TEMP\WDCA_*
- $env:LOCALAPPDATA\WDCA\

EXCLUDED PROCESSES:
- powershell.exe (when running WDCA)
- winget.exe
- cmd.exe (for WDCA installations)

JUSTIFICATION:
WDCA is a legitimate IT administration tool that:
- Automates Windows deployment tasks
- Uses standard Microsoft tools (WinGet, DISM, SFC)
- Is open-source and auditable
- Follows enterprise IT best practices

FALSE POSITIVE TRIGGERS:
- Automated script execution
- Multiple process launches
- Registry modifications for configuration
- Administrative privilege usage

"@

    $exclusionPath = "$env:USERPROFILE\Desktop\WDCA_AV_Exclusion_Request.txt"
    Set-Content -Path $exclusionPath -Value $exclusionInfo -Encoding UTF8

    [System.Windows.MessageBox]::Show(
        "Antivirus exclusion information saved to:`n$exclusionPath`n`nShare this with your IT security team to request exclusions.",
        "WDCA - Antivirus Exclusion Info",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    )
}

# Digitale Signatur prÃ¼fen (falls verfÃ¼gbar)
function Test-WDCASignature {
    <#
    .SYNOPSIS
        PrÃ¼ft die digitale Signatur von WDCA-Dateien
    #>

    try {
        $scriptPath = $PSCommandPath
        if ($scriptPath) {
            $signature = Get-AuthenticodeSignature -FilePath $scriptPath

            if ($signature.Status -eq "Valid") {
                Write-Logger "WDCA is digitally signed and verified" "SUCCESS"
                return $true
            }
        }

        Write-Logger "WDCA signature verification failed or not signed" "WARNING"
        return $false
    }
    catch {
        Write-Logger "Error checking signature: $($_.Exception.Message)" "WARNING"
        return $false
    }
}
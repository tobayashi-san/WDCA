function Set-UIEnabled {
    <#
    .SYNOPSIS
        Aktiviert oder deaktiviert UI-Elemente

    .PARAMETER Enabled
        $true um UI zu aktivieren, $false um zu deaktivieren
    #>

    param([bool]$Enabled)

    try {
        if ($global:sync.Form) {
            $global:sync.Form.Dispatcher.Invoke([action]{
                # Haupt-Buttons deaktivieren/aktivieren
                $buttonNames = @(
                    "WPFInstallSelectedApps", "WPFSelectAllApps", "WPFDeselectAllApps",
                    "WPFConfigureNetwork", "WPFEnableRDP", "WPFApplyRole",
                    "WPFRunDiagnostics", "WPFRunDISM", "WPFRunSFC", "WPFRunCHKDSK", "WPFNetworkDiagnostics",
                    "WPFCheckUpdates", "WPFInstallUpdates", "WPFUpdateApps", "WPFUpgradeApps", "WPFPrepareUpgrade",
                    "WPFRunSysprep", "WPFRunCleanup", "WPFPrepareSysprep"
                )

                foreach ($buttonName in $buttonNames) {
                    if ($global:sync[$buttonName]) {
                        $global:sync[$buttonName].IsEnabled = $Enabled
                    }
                }

                # Navigation nur bei grossen Operationen deaktivieren
                if (-not $Enabled) {
                    $navButtons = @("NavApplications", "NavSystemSetup", "NavTroubleshooting", "NavUpdates", "NavCloning")
                    foreach ($navButton in $navButtons) {
                        if ($global:sync[$navButton]) {
                            $global:sync[$navButton].IsEnabled = $false
                        }
                    }
                } else {
                    $navButtons = @("NavApplications", "NavSystemSetup", "NavTroubleshooting", "NavUpdates", "NavCloning", "NavSettings", "NavAbout")
                    foreach ($navButton in $navButtons) {
                        if ($global:sync[$navButton]) {
                            $global:sync[$navButton].IsEnabled = $true
                        }
                    }
                }
            })
        }
    }
    catch {
        Write-Logger "Error setting UI enabled state: $($_.Exception.Message)" "ERROR"
    }
}

function Update-ProgressSafe {
    <#
    .SYNOPSIS
        Thread-sichere Progress-Update Funktion

    .PARAMETER Message
        Nachricht fuer die Fortschrittsanzeige

    .PARAMETER PercentComplete
        Fortschritt in Prozent (0-100), -1 fuer unbestimmten Fortschritt
    #>

    param(
        [string]$Message,
        [int]$PercentComplete = -1
    )

    try {
        if ($global:sync.Form) {
            $global:sync.Form.Dispatcher.Invoke([action]{
                # Progress Bar aktualisieren
                if ($global:sync.WPFProgressBar) {
                    if ($PercentComplete -ge 0 -and $PercentComplete -le 100) {
                        $global:sync.WPFProgressBar.Value = $PercentComplete
                        $global:sync.WPFProgressBar.IsIndeterminate = $false
                        $global:sync.WPFProgressBar.Visibility = "Visible"
                    }
                    elseif ($PercentComplete -eq -1) {
                        $global:sync.WPFProgressBar.IsIndeterminate = $true
                        $global:sync.WPFProgressBar.Visibility = "Visible"
                    }
                    else {
                        $global:sync.WPFProgressBar.Visibility = "Collapsed"
                    }
                }

                # Status Text aktualisieren
                if ($global:sync.WPFStatusText -and $Message) {
                    $global:sync.WPFStatusText.Text = $Message
                }
            })
        }
    }
    catch {
        Write-Logger "Error updating progress: $($_.Exception.Message)" "DEBUG"
    }
}

function Add-DiagnosticResultSafe {
    <#
    .SYNOPSIS
        Thread-sichere Diagnostic Results Funktion

    .PARAMETER Text
        Text der zu den Diagnostic Results hinzugefuegt werden soll
    #>

    param([string]$Text)

    try {
        if ($global:sync.WPFDiagnosticResults) {
            $global:sync.WPFDiagnosticResults.Dispatcher.Invoke([action]{
                $global:sync.WPFDiagnosticResults.AppendText("$Text`r`n")
                $global:sync.WPFDiagnosticResults.ScrollToEnd()
            })
        }
    }
    catch {
        Write-Logger "Error adding diagnostic result: $($_.Exception.Message)" "DEBUG"
    }
}

function Reset-ProgressBar {
    <#
    .SYNOPSIS
        Versteckt und resettet die Progress Bar
    #>

    try {
        if ($global:sync.WPFProgressBar) {
            $global:sync.WPFProgressBar.Dispatcher.Invoke([action]{
                $global:sync.WPFProgressBar.Value = 0
                $global:sync.WPFProgressBar.IsIndeterminate = $false
                $global:sync.WPFProgressBar.Visibility = "Collapsed"
            })
        }
    }
    catch {
        Write-Logger "Error resetting progress bar: $($_.Exception.Message)" "DEBUG"
    }
}

function Show-OperationDialog {
    <#
    .SYNOPSIS
        Zeigt einen modalen Dialog fuer laufende Operationen

    .PARAMETER Title
        Titel des Dialogs

    .PARAMETER Message
        Nachricht im Dialog

    .PARAMETER AllowCancel
        Ob der Dialog einen Cancel-Button haben soll
    #>

    param(
        [string]$Title = "Operation in Progress",
        [string]$Message = "Please wait...",
        [bool]$AllowCancel = $true
    )

    # Einfache Implementation - koennte spaeter erweitert werden
    try {
        if ($global:sync.Form -and $AllowCancel) {
            $result = [System.Windows.MessageBox]::Show(
                $Message + "`n`nPress OK to continue or Cancel to stop.",
                "WDCA - $Title",
                [System.Windows.MessageBoxButton]::OKCancel,
                [System.Windows.MessageBoxImage]::Information
            )

            return $result -eq [System.Windows.MessageBoxResult]::OK
        }
    }
    catch {
        Write-Logger "Error showing operation dialog: $($_.Exception.Message)" "ERROR"
    }

    return $true
}

function Test-UIResponsive {
    <#
    .SYNOPSIS
        Testet ob die UI noch responsive ist
    #>

    try {
        if ($global:sync.Form) {
            $responsive = $false
            $global:sync.Form.Dispatcher.Invoke([action]{
                $responsive = $global:sync.Form.IsLoaded
            }, [System.Windows.Threading.DispatcherPriority]::Normal, [System.Threading.CancellationToken]::None, [System.TimeSpan]::FromMilliseconds(100))

            return $responsive
        }
    }
    catch {
        return $false
    }

    return $false
}

function Update-UIStatus {
    <#
    .SYNOPSIS
        Aktualisiert verschiedene UI-Status-Indikatoren

    .PARAMETER StatusMessage
        Status-Nachricht

    .PARAMETER OperationsCount
        Anzahl aktiver Operationen

    .PARAMETER LastOperation
        Name der letzten Operation
    #>

    param(
        [string]$StatusMessage,
        [int]$OperationsCount = 0,
        [string]$LastOperation = ""
    )

    try {
        if ($global:sync.Form) {
            $global:sync.Form.Dispatcher.Invoke([action]{
                # Status Text aktualisieren
                if ($global:sync.WPFStatusText -and $StatusMessage) {
                    $statusWithIndicator = if ($OperationsCount -gt 0) {
                        "$StatusMessage ($OperationsCount active)"
                    } else {
                        $StatusMessage
                    }
                    $global:sync.WPFStatusText.Text = $statusWithIndicator
                }

                # Titel Bar aktualisieren falls noetig
                if ($global:sync.Form.Title -and $OperationsCount -gt 0) {
                    if (-not $global:sync.Form.Title.Contains("- Running")) {
                        $global:sync.Form.Title = "WDCA - Running Operation"
                    }
                } elseif ($global:sync.Form.Title -and $OperationsCount -eq 0) {
                    $global:sync.Form.Title = "Windows Deployment and Configuration Assistant"
                }
            })
        }
    }
    catch {
        Write-Logger "Error updating UI status: $($_.Exception.Message)" "DEBUG"
    }
}
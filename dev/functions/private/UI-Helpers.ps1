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


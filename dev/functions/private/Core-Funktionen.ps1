function Set-WDCATheme {
    <#
    .SYNOPSIS
        Applies a theme to the WDCA application

    .PARAMETER ThemeName
        Name of the theme to apply (Dark, Light)
    #>

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Dark", "Light")]
        [string]$ThemeName
    )

    if (-not $global:WDCAThemes) {
        Initialize-ThemeManager
    }

    $theme = $global:WDCAThemes[$ThemeName]

    if (-not $theme) {
        Write-Logger "Theme '$ThemeName' not found" "ERROR"
        return
    }

    try {
        Write-Logger "Applying theme: $ThemeName" "INFO"

        # Update resource dictionary with new theme colors
        if ($global:sync.Form -and $global:sync.Form.Resources) {
            $resources = $global:sync.Form.Resources

            # Update color resources
            foreach ($colorName in $theme.Keys) {
                # Skip non-color properties
                if ($colorName -like "*Opacity" -or $colorName -like "*Radius" -or $colorName -like "*Thickness") {
                    continue
                }

                $resourceKey = "${colorName}Brush"
                $colorValue = $theme[$colorName]

                try {
                    $brush = New-Object System.Windows.Media.SolidColorBrush
                    $brush.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($colorValue)

                    if ($resources.Contains($resourceKey)) {
                        $resources[$resourceKey] = $brush
                    } else {
                        $resources.Add($resourceKey, $brush)
                    }
                }
                catch {
                    Write-Logger "Error setting color resource $resourceKey`: $($_.Exception.Message)" "DEBUG"
                }
            }

            Write-Logger "Theme '$ThemeName' applied successfully" "INFO"
        }
    }
    catch {
        Write-Logger "Error applying theme '$ThemeName': $($_.Exception.Message)" "ERROR"
    }
}

function Update-UI {
    <#
    .SYNOPSIS
        Thread-sichere UI-Updates (vereinfacht)
    #>
    param(
        [string]$Status = "",
        [int]$Progress = -1,
        [bool]$EnableButtons = $true
    )

    if (-not $global:sync.Form) { return }

    try {
        $global:sync.Form.Dispatcher.Invoke([action]{
            # Status aktualisieren
            if ($Status -and $global:sync.WPFStatusText) {
                $global:sync.WPFStatusText.Text = $Status
            }

            # Progress aktualisieren
            if ($global:sync.WPFProgressBar) {
                if ($Progress -ge 0 -and $Progress -le 100) {
                    $global:sync.WPFProgressBar.Value = $Progress
                    $global:sync.WPFProgressBar.IsIndeterminate = $false
                    $global:sync.WPFProgressBar.Visibility = "Visible"
                } elseif ($Progress -eq -1) {
                    $global:sync.WPFProgressBar.IsIndeterminate = $true
                    $global:sync.WPFProgressBar.Visibility = "Visible"
                } else {
                    $global:sync.WPFProgressBar.Visibility = "Collapsed"
                }
            }

            # Buttons aktivieren/deaktivieren
            $buttonNames = @(
                "WPFInstallSelectedApps", "WPFSelectAllApps", "WPFDeselectAllApps",
                "WPFConfigureNetwork", "WPFEnableRDP", "WPFRunDiagnostics",
                "WPFRunDISM", "WPFRunSFC", "WPFRunCHKDSK", "WPFUpdateApps",
                "WPFRunCleanup", "WPFRefreshDebloatList", "WPFUninstallSelected"
            )

            foreach ($buttonName in $buttonNames) {
                if ($global:sync[$buttonName]) {
                    $global:sync[$buttonName].IsEnabled = $EnableButtons
                }
            }
        })
    }
    catch {
        Write-Logger "UI update error: $($_.Exception.Message)" "ERROR"
    }
}

function Initialize-WDCAConsole {
    try {
        Write-Logger "Initializing console" "INFO"

        $global:ConsoleRunspace = [runspacefactory]::CreateRunspace()
        $global:ConsoleRunspace.Open()

        $global:ConsoleState = @{
            IsVisible = $false; IsRunning = $false; CommandHistory = @()
        }

        # Event handlers setzen
        if ($global:sync.WPFToggleConsole) {
            $global:sync.WPFToggleConsole.Add_Click({ Toggle-Console })
        }

        if ($global:sync.WPFClearConsole) {
            $global:sync.WPFClearConsole.Add_Click({ Clear-Console })
        }

        if ($global:sync.WPFExecuteCommand) {
            $global:sync.WPFExecuteCommand.Add_Click({ Execute-ConsoleCommand })
        }

        if ($global:sync.WPFConsoleInput) {
            $global:sync.WPFConsoleInput.Add_KeyDown({
                param($sender, $e)
                if ($e.Key -eq "Return") { Execute-ConsoleCommand }
            })
        }

        Write-Logger "Console initialized" "SUCCESS"
    }
    catch {
        Write-Logger "Console init error: $($_.Exception.Message)" "ERROR"
    }
}

function Add-ConsoleOutput {
    param([string]$Text, [string]$Type = "Output")

    if (-not $global:sync.WPFConsoleOutput) { return }

    try {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $formattedText = "[$timestamp] $Text`r`n"

        if ($global:sync.Form.Dispatcher.CheckAccess()) {
            $global:sync.WPFConsoleOutput.AppendText($formattedText)
        } else {
            $global:sync.Form.Dispatcher.Invoke([action]{
                $global:sync.WPFConsoleOutput.AppendText($formattedText)
            })
        }
    }
    catch { }
}

function Clear-Console {
    if ($global:sync.WPFConsoleOutput) {
        $global:sync.WPFConsoleOutput.Text = "PowerShell Console`r`nPS C:\> "
    }
}


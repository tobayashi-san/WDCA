# Aktualisierte Write-Progress-Logger.ps1 - ERSETZT die bestehende Datei

function Write-Progress-Logger {
    <#
    .SYNOPSIS
        Thread-sichere Progress-Logging Funktion

    .DESCRIPTION
        Ersetzt die alte Write-Progress-Logger Funktion mit thread-sicherem Design
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [int]$PercentComplete = -1
    )

    # Use the new thread-safe function
    Update-ProgressSafe -Message $Message -PercentComplete $PercentComplete
}

function Add-DiagnosticResult {
    <#
    .SYNOPSIS
        Thread-sichere Diagnostic Results Funktion

    .DESCRIPTION
        Ersetzt die alte Add-DiagnosticResult Funktion mit thread-sicherem Design
    #>

    param([string]$Text)

    # Use the new thread-safe function
    Add-DiagnosticResultSafe -Text $Text
}

function Clear-DiagnosticResults {
    <#
    .SYNOPSIS
        Thread-sichere Clear Results Funktion
    #>

    try {
        if ($global:sync.WPFDiagnosticResults) {
            $global:sync.WPFDiagnosticResults.Dispatcher.Invoke([action]{
                $global:sync.WPFDiagnosticResults.Text = ""
            })
        }
    }
    catch {
        Write-Logger "Error clearing diagnostic results: $($_.Exception.Message)" "ERROR"
    }
}

# Runspace Pool Management
function Initialize-RunspacePool {
    <#
    .SYNOPSIS
        Initialisiert den Runspace Pool fÃ¼r bessere Performance
    #>

    if (-not $global:RunspacePool) {
        try {
            $global:RunspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
            $global:RunspacePool.Open()
            Write-Logger "Runspace pool initialized with 1-5 threads" "INFO"
        }
        catch {
            Write-Logger "Error initializing runspace pool: $($_.Exception.Message)" "ERROR"
        }
    }
}

function Close-RunspacePool {
    <#
    .SYNOPSIS
        SchlieÃŸt den Runspace Pool beim Beenden
    #>

    if ($global:RunspacePool) {
        try {
            $global:RunspacePool.Close()
            $global:RunspacePool.Dispose()
            $global:RunspacePool = $null
            Write-Logger "Runspace pool closed" "INFO"
        }
        catch {
            Write-Logger "Error closing runspace pool: $($_.Exception.Message)" "ERROR"
        }
    }
}

# Job Management fÃ¼r langanhaltende Operationen
function Get-ActiveAsyncOperations {
    <#
    .SYNOPSIS
        Zeigt aktive async Operationen an
    #>

    if ($global:ActiveOperations) {
        return $global:ActiveOperations.Keys
    }
    return @()
}

function Stop-AllAsyncOperations {
    <#
    .SYNOPSIS
        Stoppt alle aktiven async Operationen
    #>

    if ($global:ActiveOperations) {
        foreach ($operationName in $global:ActiveOperations.Keys) {
            try {
                $operation = $global:ActiveOperations[$operationName]
                if ($operation.Timer) {
                    $operation.Timer.Stop()
                }
                if ($operation.PowerShell) {
                    $operation.PowerShell.Stop()
                    $operation.PowerShell.Dispose()
                }
                Write-Logger "Stopped async operation: $operationName" "INFO"
            }
            catch {
                Write-Logger "Error stopping operation $operationName`: $($_.Exception.Message)" "ERROR"
            }
        }
        $global:ActiveOperations.Clear()
    }

    # Re-enable UI
    Set-UIEnabled -Enabled $true
    Reset-ProgressBar
}

# Enhanced UI State Management
function Save-UIState {
    <#
    .SYNOPSIS
        Speichert den aktuellen UI-Status
    #>

    if (-not $global:UIStateStack) {
        $global:UIStateStack = @()
    }

    $currentState = @{
        ButtonStates = @{}
        ProgressVisible = $false
        StatusText = ""
    }

    # Save button states
    $buttonNames = @(
        "WPFInstallSelectedApps", "WPFSelectAllApps", "WPFDeselectAllApps",
        "WPFConfigureNetwork", "WPFEnableRDP", "WPFApplyRole",
        "WPFRunDiagnostics", "WPFRunDISM", "WPFRunSFC", "WPFRunCHKDSK", "WPFNetworkDiagnostics",
        "WPFCheckUpdates", "WPFInstallUpdates", "WPFUpdateApps", "WPFUpgradeApps",
        "WPFRunSysprep", "WPFRunCleanup", "WPFPrepareSysprep"
    )

    foreach ($buttonName in $buttonNames) {
        if ($global:sync[$buttonName]) {
            $currentState.ButtonStates[$buttonName] = $global:sync[$buttonName].IsEnabled
        }
    }

    # Save progress state
    if ($global:sync.WPFProgressBar) {
        $currentState.ProgressVisible = $global:sync.WPFProgressBar.Visibility -eq "Visible"
    }

    # Save status text
    if ($global:sync.WPFStatusText) {
        $currentState.StatusText = $global:sync.WPFStatusText.Text
    }

    $global:UIStateStack += $currentState
}

function Restore-UIState {
    <#
    .SYNOPSIS
        Stellt den gespeicherten UI-Status wieder her
    #>

    if ($global:UIStateStack -and $global:UIStateStack.Count -gt 0) {
        $lastState = $global:UIStateStack[$global:UIStateStack.Count - 1]
        $global:UIStateStack = $global:UIStateStack[0..($global:UIStateStack.Count - 2)]

        try {
            if ($global:sync.Form) {
                $global:sync.Form.Dispatcher.Invoke([action]{
                    # Restore button states
                    foreach ($buttonName in $lastState.ButtonStates.Keys) {
                        if ($global:sync[$buttonName]) {
                            $global:sync[$buttonName].IsEnabled = $lastState.ButtonStates[$buttonName]
                        }
                    }

                    # Restore progress state
                    if ($global:sync.WPFProgressBar) {
                        $global:sync.WPFProgressBar.Visibility = if ($lastState.ProgressVisible) { "Visible" } else { "Collapsed" }
                    }

                    # Restore status text
                    if ($global:sync.WPFStatusText -and $lastState.StatusText) {
                        $global:sync.WPFStatusText.Text = $lastState.StatusText
                    }
                })
            }
        }
        catch {
            Write-Logger "Error restoring UI state: $($_.Exception.Message)" "ERROR"
        }
    }
}
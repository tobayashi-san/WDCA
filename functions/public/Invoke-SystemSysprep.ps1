function Invoke-SystemSysprep {
    <#
    .SYNOPSIS
        Runs Windows Sysprep for system imaging

    .DESCRIPTION
        Executes Sysprep with user-selected options to prepare the system for imaging
    #>

    Write-Logger "Starting Sysprep process" "INFO"

    # Get Sysprep options from UI
    $generalize = if ($sync.WPFSysprepGeneralize) { $sync.WPFSysprepGeneralize.IsChecked } else { $true }
    $oobe = if ($sync.WPFSysprepOOBE) { $sync.WPFSysprepOOBE.IsChecked } else { $true }
    $shutdown = if ($sync.WPFSysprepShutdown) { $sync.WPFSysprepShutdown.IsChecked } else { $true }

    # Build Sysprep command arguments
    $sysprepArgs = @("/quiet")

    if ($generalize) {
        $sysprepArgs += "/generalize"
    }

    if ($oobe) {
        $sysprepArgs += "/oobe"
    }
    else {
        $sysprepArgs += "/audit"
    }

    if ($shutdown) {
        $sysprepArgs += "/shutdown"
    }
    else {
        $sysprepArgs += "/reboot"
    }

    # Show final warning
    $warningMessage = "CRITICAL WARNING`n`n"
    $warningMessage += "Sysprep will prepare this system for imaging and will:`n`n"
    if ($generalize) { $warningMessage += "- Remove system-specific information (Generalize)`n" }
    if ($oobe) { $warningMessage += "- Boot to Out-of-Box Experience on next start`n" }
    if ($shutdown) { $warningMessage += "- Shutdown the computer when complete`n" } else { $warningMessage += "- Restart the computer when complete`n" }
    $warningMessage += "`n This action CANNOT be undone!`n`n"
    $warningMessage += "Command: sysprep.exe $($sysprepArgs -join ' ')`n`n"
    $warningMessage += "Continue with Sysprep?"

    $confirmResult = [System.Windows.MessageBox]::Show(
        $warningMessage,
        "WDCA - Sysprep Warning",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Sysprep cancelled by user" "INFO"
        return
    }

    try {
        Write-Logger "Running Sysprep with arguments: $($sysprepArgs -join ' ')" "INFO"
        Write-Progress-Logger "Preparing system for imaging..." 50

        # Run Sysprep
        $sysprepPath = "$env:SystemRoot\System32\Sysprep\sysprep.exe"

        if (-not (Test-Path $sysprepPath)) {
            throw "Sysprep.exe not found at $sysprepPath"
        }

        Write-Logger "Executing Sysprep - System will shutdown/restart when complete" "INFO"

        # Start Sysprep process
        Start-Process -FilePath $sysprepPath -ArgumentList $sysprepArgs -NoNewWindow

        Write-Logger "Sysprep process started successfully" "INFO"
        [System.Windows.MessageBox]::Show("Sysprep has been started. The system will shutdown or restart when the process completes.", "WDCA - Sysprep Started", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    }
    catch {
        Write-Logger "Error running Sysprep: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show("Error running Sysprep: $($_.Exception.Message)", "WDCA - Sysprep Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
    finally {
        # Reset progress bar
        if ($sync.WPFProgressBar) {
            $sync.WPFProgressBar.Dispatcher.Invoke([action]{
                $sync.WPFProgressBar.Value = 0
            })
        }
    }
}
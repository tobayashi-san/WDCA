function Invoke-SysprepPreparation {
    <#
    .SYNOPSIS
        Prepares the system for Sysprep by running cleanup and checks

    .DESCRIPTION
        Performs pre-Sysprep tasks like cleanup and validation
    #>

    Write-Logger "Preparing system for Sysprep" "INFO"

    try {
        Write-Progress-Logger "Checking Sysprep prerequisites..." 20

        # Check if system is domain-joined (may need special handling)
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        if ($computerSystem.PartOfDomain) {
            Write-Logger "System is domain-joined. Consider running Sysprep in audit mode first." "WARNING"
            $domainWarning = [System.Windows.MessageBox]::Show(
                "This system is joined to a domain. This may affect Sysprep operation.`n`nContinue with preparation?",
                "WDCA - Domain Warning",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )

            if ($domainWarning -ne [System.Windows.MessageBoxResult]::Yes) {
                return
            }
        }

        Write-Progress-Logger "Running pre-Sysprep cleanup..." 50

        # Run cleanup automatically
        Invoke-PreCloneCleanup

        Write-Progress-Logger "Checking Windows activation..." 70

        # Check Windows activation status
        try {
            $licensing = Get-WmiObject -Class SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
            if ($licensing) {
                Write-Logger "Windows is activated and ready for Sysprep" "INFO"
            }
            else {
                Write-Logger "Windows activation status unclear - proceed with caution" "WARNING"
            }
        }
        catch {
            Write-Logger "Could not check Windows activation status" "WARNING"
        }

        Write-Progress-Logger "System preparation completed" 100

        $message = "System preparation for Sysprep completed successfully!`n`n"
        $message += "The system is now ready for Sysprep. You can proceed to run Sysprep when ready."

        Write-Logger "System preparation for Sysprep completed" "INFO"
        [System.Windows.MessageBox]::Show($message, "WDCA - Preparation Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    }
    catch {
        Write-Logger "Error during Sysprep preparation: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show("Error during preparation: $($_.Exception.Message)", "WDCA - Preparation Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
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
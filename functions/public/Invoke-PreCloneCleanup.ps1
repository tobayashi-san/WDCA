function Invoke-PreCloneCleanup {
    <#
    .SYNOPSIS
        Performs system cleanup before cloning

    .DESCRIPTION
        Cleans temporary files, logs, and other data to reduce image size
    #>

    Write-Logger "Starting pre-clone cleanup" "INFO"

    # Get cleanup options from UI
    $cleanTemp = if ($sync.WPFCleanupTemp) { $sync.WPFCleanupTemp.IsChecked } else { $true }
    $cleanLogs = if ($sync.WPFCleanupLogs) { $sync.WPFCleanupLogs.IsChecked } else { $true }
    $cleanRecycle = if ($sync.WPFCleanupRecycle) { $sync.WPFCleanupRecycle.IsChecked } else { $true }

    $confirmResult = [System.Windows.MessageBox]::Show(
        "Perform pre-clone cleanup?`n`nThis will remove temporary files, logs, and other unnecessary data.",
        "WDCA - Pre-Clone Cleanup",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Logger "Pre-clone cleanup cancelled by user" "INFO"
        return
    }

    try {
        $cleanupResults = @()

        Write-Progress-Logger "Starting cleanup process..." 10

        if ($cleanTemp) {
            Write-Progress-Logger "Cleaning temporary files..." 25
            $tempCleaned = Clear-TemporaryFiles
            $cleanupResults += "Temporary files: $tempCleaned"
        }

        if ($cleanLogs) {
            Write-Progress-Logger "Cleaning event logs..." 50
            $logsCleaned = Clear-EventLogs
            $cleanupResults += "Event logs: $logsCleaned"
        }

        if ($cleanRecycle) {
            Write-Progress-Logger "Emptying recycle bin..." 75
            $recycleCleaned = Clear-RecycleBin
            $cleanupResults += "Recycle bin: $recycleCleaned"
        }

        Write-Progress-Logger "Running disk cleanup..." 90
        Invoke-DiskCleanup

        Write-Progress-Logger "Cleanup completed" 100

        $resultMessage = "Pre-clone cleanup completed successfully!`n`n" + ($cleanupResults -join "`n")
        Write-Logger "Pre-clone cleanup completed" "INFO"
        [System.Windows.MessageBox]::Show($resultMessage, "WDCA - Cleanup Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    }
    catch {
        Write-Logger "Error during pre-clone cleanup: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show("Error during cleanup: $($_.Exception.Message)", "WDCA - Cleanup Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
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
function Invoke-PreCloneCleanup {
    <#
    .SYNOPSIS
        Performs system cleanup before cloning with user selection

    .DESCRIPTION
        Cleans temporary files, logs, and other data to reduce image size
        Allows user to select which cleanup operations to perform
    #>

    Write-Logger "Starting pre-clone cleanup" "INFO"

    # Get cleanup options from UI
    $cleanTemp = if ($global:sync.WPFCleanupTemp) { $global:sync.WPFCleanupTemp.IsChecked } else { $true }
    $cleanLogs = if ($global:sync.WPFCleanupLogs) { $global:sync.WPFCleanupLogs.IsChecked } else { $true }
    $cleanRecycle = if ($global:sync.WPFCleanupRecycle) { $global:sync.WPFCleanupRecycle.IsChecked } else { $true }

    Write-Logger "Cleanup options selected - Temp: $cleanTemp, Logs: $cleanLogs, Recycle: $cleanRecycle" "INFO"

    # Build confirmation message based on selected options
    $operations = @()
    if ($cleanTemp) { $operations += "Temporary files" }
    if ($cleanLogs) { $operations += "Event logs" }
    if ($cleanRecycle) { $operations += "Recycle bin" }

    if ($operations.Count -eq 0) {
        Write-Logger "No cleanup operations selected" "WARNING"
        [System.Windows.MessageBox]::Show(
            "No cleanup operations selected. Please select at least one option.",
            "WDCA - No Selection",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
        return
    }

    $operationsText = $operations -join ", "
    $confirmResult = [System.Windows.MessageBox]::Show(
        "Perform pre-clone cleanup?`n`nThis will clean: $operationsText`n`nThis action cannot be undone. Continue?",
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
        $totalSpace = 0

        Write-Logger "Starting cleanup operations..." "INFO"
        Update-ProgressSafe -Message "Starting cleanup..." -PercentComplete 10

        if ($cleanTemp) {
            Update-ProgressSafe -Message "Cleaning temporary files..." -PercentComplete 25
            try {
                $tempResult = Clear-TemporaryFiles
                $cleanupResults += "Temporary files: $tempResult"
                Write-Logger "Temporary files cleanup completed: $tempResult" "SUCCESS"

                # Extract space freed if format is "X.XX MB cleaned"
                if ($tempResult -match '([\d\.]+)\s*MB') {
                    $totalSpace += [double]$matches[1]
                }
            }
            catch {
                $error = "Error cleaning temporary files: $($_.Exception.Message)"
                $cleanupResults += $error
                Write-Logger $error "ERROR"
            }
        }

        if ($cleanLogs) {
            Update-ProgressSafe -Message "Cleaning event logs..." -PercentComplete 50
            try {
                $logResult = Clear-EventLogs
                $cleanupResults += "Event logs: $logResult"
                Write-Logger "Event logs cleanup completed: $logResult" "SUCCESS"
            }
            catch {
                $error = "Error cleaning event logs: $($_.Exception.Message)"
                $cleanupResults += $error
                Write-Logger $error "ERROR"
            }
        }

        if ($cleanRecycle) {
            Update-ProgressSafe -Message "Emptying recycle bin..." -PercentComplete 75
            try {
                $recycleResult = Clear-WDCARecycleBin
                $cleanupResults += "Recycle bin: $recycleResult"
                Write-Logger "Recycle bin cleanup completed: $recycleResult" "SUCCESS"
            }
            catch {
                $error = "Error emptying recycle bin: $($_.Exception.Message)"
                $cleanupResults += $error
                Write-Logger $error "ERROR"
            }
        }

        # Additional cleanup operations
        Update-ProgressSafe -Message "Running additional cleanup..." -PercentComplete 85

        # Clear Windows Update cache
        try {
            $updateCacheSize = 0
            $updateCachePath = "$env:SystemRoot\SoftwareDistribution\Download"
            if (Test-Path $updateCachePath) {
                $files = Get-ChildItem -Path $updateCachePath -Recurse -File -ErrorAction SilentlyContinue
                if ($files) {
                    $updateCacheSize = ($files | Measure-Object -Property Length -Sum).Sum / 1MB
                }

                # Stop Windows Update service
                Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2

                # Clear the download folder
                Remove-Item -Path "$updateCachePath\*" -Recurse -Force -ErrorAction SilentlyContinue

                # Restart Windows Update service
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue

                $cleanupResults += "Windows Update cache: $([math]::Round($updateCacheSize, 2)) MB cleaned"
                $totalSpace += $updateCacheSize
                Write-Logger "Windows Update cache cleaned: $([math]::Round($updateCacheSize, 2)) MB" "SUCCESS"
            }
        } catch {
            $error = "Windows Update cache: Error - $($_.Exception.Message)"
            $cleanupResults += $error
            Write-Logger $error "WARNING"
        }

        # Clear thumbnail cache
        try {
            $thumbCachePath = "$env:LocalAppData\Microsoft\Windows\Explorer"
            $thumbFiles = Get-ChildItem -Path $thumbCachePath -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue
            if ($thumbFiles) {
                $thumbSize = ($thumbFiles | Measure-Object -Property Length -Sum).Sum / 1MB
                $thumbFiles | Remove-Item -Force -ErrorAction SilentlyContinue
                $cleanupResults += "Thumbnail cache: $([math]::Round($thumbSize, 2)) MB cleaned"
                $totalSpace += $thumbSize
                Write-Logger "Thumbnail cache cleaned: $([math]::Round($thumbSize, 2)) MB" "SUCCESS"
            }
        } catch {
            $error = "Thumbnail cache: Error - $($_.Exception.Message)"
            $cleanupResults += $error
            Write-Logger $error "WARNING"
        }

        # Clear Windows Error Reporting
        try {
            $werPath = "$env:ProgramData\Microsoft\Windows\WER"
            if (Test-Path $werPath) {
                $werFiles = Get-ChildItem -Path $werPath -Recurse -File -ErrorAction SilentlyContinue
                if ($werFiles) {
                    $werSize = ($werFiles | Measure-Object -Property Length -Sum).Sum / 1MB
                    Remove-Item -Path "$werPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                    $cleanupResults += "Error reports: $([math]::Round($werSize, 2)) MB cleaned"
                    $totalSpace += $werSize
                    Write-Logger "Error reports cleaned: $([math]::Round($werSize, 2)) MB" "SUCCESS"
                }
            }
        } catch {
            $error = "Error reports: Error - $($_.Exception.Message)"
            $cleanupResults += $error
            Write-Logger $error "WARNING"
        }

        Update-ProgressSafe -Message "Cleanup completed" -PercentComplete 100

        # Create detailed report
        $reportContent = @()
        $reportContent += "=== PRE-CLONE CLEANUP REPORT ==="
        $reportContent += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $reportContent += "Total space freed: $([math]::Round($totalSpace, 2)) MB"
        $reportContent += ""
        $reportContent += "=== OPERATIONS PERFORMED ==="
        foreach ($result in $cleanupResults) {
            $reportContent += $result
        }
        $reportContent += ""
        $reportContent += "=== SUMMARY ==="
        $reportContent += "Operations completed: $(if($cleanTemp){'Temp '})$(if($cleanLogs){'Logs '})$(if($cleanRecycle){'Recycle '})"
        $reportContent += "Cleanup completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

        # Save report
        $reportPath = "$env:USERPROFILE\Desktop\WDCA_Cleanup_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        Set-Content -Path $reportPath -Value ($reportContent -join "`r`n") -Encoding UTF8

        # Show success message
        $message = "Pre-clone cleanup completed successfully!`n`n"
        $message += "Total space freed: $([math]::Round($totalSpace, 2)) MB`n"
        $message += "Operations performed:`n"
        if ($cleanTemp) { $message += "• Temporary files`n" }
        if ($cleanLogs) { $message += "• Event logs`n" }
        if ($cleanRecycle) { $message += "• Recycle bin`n" }
        $message += "• Windows Update cache`n"
        $message += "• Thumbnail cache`n"
        $message += "• Error reports`n"
        $message += "`nDetailed report saved to:`n$reportPath"

        Write-Logger "Pre-clone cleanup completed successfully - $([math]::Round($totalSpace, 2)) MB freed" "SUCCESS"

        [System.Windows.MessageBox]::Show(
            $message,
            "WDCA - Cleanup Complete",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
    }
    catch {
        Write-Logger "Error during pre-clone cleanup: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Error during cleanup: $($_.Exception.Message)",
            "WDCA - Cleanup Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
    finally {
        # Reset progress bar
        Reset-ProgressBar
    }
}

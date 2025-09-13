

function Stop-AsyncOperation {
    <#
    .SYNOPSIS
        Stops a running async operation
    #>

    param(
        [string]$OperationId,
        [string]$Reason = "User Request"
    )

    try {
        if (-not $global:AsyncOperations -or -not $global:AsyncOperations.ContainsKey($OperationId)) {
            return
        }

        $context = $global:AsyncOperations[$OperationId]

        Write-Logger "Stopping async operation: $($context.OperationName) - Reason: $Reason" "WARNING" -Category "AsyncOps"

        $context.IsCancelled = $true
        $context.IsCompleted = $true

        # Stop PowerShell execution
        if ($context.PowerShell -and -not $context.AsyncResult.IsCompleted) {
            try {
                $context.PowerShell.Stop()
                Start-Sleep -Milliseconds 500
            }
            catch {
                Write-Logger "Error stopping PowerShell instance: $($_.Exception.Message)" "WARNING" -Category "AsyncOps"
            }
        }

        # Cleanup
        Cleanup-AsyncOperation -OperationId $OperationId

        Set-WDCAStatus "Operation cancelled: $($context.OperationName)"

    }
    catch {
        Write-Logger "Error stopping async operation $OperationId`: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
    }
}

function Cleanup-AsyncOperation {
    <#
    .SYNOPSIS
        Cleans up resources from an async operation
    #>

    param([string]$OperationId)

    try {
        if ($global:AsyncOperations -and $global:AsyncOperations.ContainsKey($OperationId)) {
            $context = $global:AsyncOperations[$OperationId]

            # Dispose PowerShell instance if not already done
            if ($context.PowerShell) {
                try {
                    $context.PowerShell.Dispose()
                }
                catch {
                    Write-Logger "Error disposing PowerShell instance: $($_.Exception.Message)" "WARNING" -Category "AsyncOps"
                }
            }

            # Remove from tracking
            $global:AsyncOperations.TryRemove($OperationId, [ref]$null) | Out-Null
        }

        # Check if this was the last operation
        if (-not $global:AsyncOperations -or $global:AsyncOperations.Count -eq 0) {
            # Reset UI state
            if ($global:sync.Form) {
                try {
                    $global:sync.Form.Dispatcher.Invoke([System.Action]{
                        # Re-enable UI elements
                        $buttonNames = @(
                            "WPFInstallSelectedApps", "WPFSelectAllApps", "WPFDeselectAllApps",
                            "WPFConfigureNetwork", "WPFEnableRDP",
                            "WPFRunDiagnostics", "WPFRunDISM", "WPFRunSFC", "WPFRunCHKDSK",
                            "WPFUpdateApps", "WPFListAppUpdate",
                            "WPFRunCleanup", "WPFRefreshDebloatList", "WPFUninstallSelected"
                        )

                        foreach ($buttonName in $buttonNames) {
                            if ($global:sync[$buttonName]) {
                                $global:sync[$buttonName].IsEnabled = $true
                            }
                        }

                        # Reset progress bar
                        if ($global:sync.WPFProgressBar) {
                            $global:sync.WPFProgressBar.Value = 0
                            $global:sync.WPFProgressBar.IsIndeterminate = $false
                            $global:sync.WPFProgressBar.Visibility = "Collapsed"
                        }
                    }, [System.Windows.Threading.DispatcherPriority]::Normal)
                } catch {
                    Write-Logger "Error resetting UI state: $($_.Exception.Message)" "WARNING" -Category "AsyncOps"
                }
            }

            Set-WDCAStatus "Ready"

            # Trigger garbage collection
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }

    }
    catch {
        Write-Logger "Error during async operation cleanup: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
    }
}

function Stop-AllAsyncOperations {
    <#
    .SYNOPSIS
        Stops all running async operations
    #>

    try {
        if (-not $global:AsyncOperations -or $global:AsyncOperations.Count -eq 0) {
            return
        }

        Write-Logger "Stopping all async operations ($($global:AsyncOperations.Count) active)" "WARNING" -Category "AsyncOps"

        # Get all operation IDs to avoid modification during enumeration
        $operationIds = @()
        foreach ($key in $global:AsyncOperations.Keys) {
            $operationIds += $key
        }

        foreach ($operationId in $operationIds) {
            Stop-AsyncOperation -OperationId $operationId -Reason "Application Shutdown"
        }

        # Force cleanup if anything remains
        if ($global:AsyncOperations) {
            $global:AsyncOperations.Clear()
        }

        Write-Logger "All async operations stopped" "INFO" -Category "AsyncOps"

    }
    catch {
        Write-Logger "Error stopping all async operations: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
    }
}

function Get-ActiveAsyncOperations {
    <#
    .SYNOPSIS
        Returns information about active async operations
    #>

    if (-not $global:AsyncOperations) {
        return @()
    }

    $activeOps = @()
    foreach ($key in $global:AsyncOperations.Keys) {
        try {
            $context = $global:AsyncOperations[$key]
            if (-not $context.IsCompleted -and -not $context.IsCancelled) {
                $elapsed = ((Get-Date) - $context.StartTime).TotalSeconds
                $activeOps += [PSCustomObject]@{
                    OperationId = $context.OperationId
                    OperationName = $context.OperationName
                    ElapsedSeconds = [math]::Round($elapsed, 1)
                    StartTime = $context.StartTime
                    AllowCancel = $context.AllowCancel
                }
            }
        } catch {
            # Skip problematic entries
        }
    }

    return $activeOps
}
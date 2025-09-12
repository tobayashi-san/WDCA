function Start-AsyncOperation {
    <#
    .SYNOPSIS
        Fixed async operation manager without problematic timers
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ScriptBlock]$ProgressCallback,

        [Parameter(Mandatory = $false)]
        [ScriptBlock]$CompletedCallback,

        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Background Operation",

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 3600,

        [Parameter(Mandatory = $false)]
        [bool]$AllowCancel = $true
    )

    try {
        Write-Logger "Starting async operation: $OperationName" "INFO" -Category "AsyncOps"

        # Initialize async operations tracking if not exists
        if (-not $global:AsyncOperations) {
            $global:AsyncOperations = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        }

        # Generate unique operation ID
        $operationId = [System.Guid]::NewGuid().ToString()

        # Initialize or get runspace pool
        $runspacePool = Get-RunspacePool

        # Create PowerShell instance
        $powershell = [PowerShell]::Create()
        $powershell.RunspacePool = $runspacePool

        # Enhanced script wrapper with better error handling
        $wrappedScript = {
            param($ScriptBlock, $OperationName, $OperationId)

            $result = @{
                Success = $false
                Result = $null
                Error = $null
                OperationId = $OperationId
                StartTime = Get-Date
                EndTime = $null
                Duration = $null
            }

            try {
                Write-Verbose "Executing async operation: $OperationName"
                $result.Result = Invoke-Command -ScriptBlock $ScriptBlock
                $result.Success = $true
                Write-Verbose "Async operation completed successfully: $OperationName"
            }
            catch {
                $result.Error = @{
                    Message = $_.Exception.Message
                    FullError = $_.Exception.ToString()
                    ScriptStackTrace = $_.ScriptStackTrace
                }
                Write-Verbose "Async operation failed: $OperationName - $($_.Exception.Message)"
            }
            finally {
                $result.EndTime = Get-Date
                $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds
            }

            return $result
        }

        # Add script to PowerShell instance
        [void]$powershell.AddScript($wrappedScript).AddParameter("ScriptBlock", $ScriptBlock).AddParameter("OperationName", $OperationName).AddParameter("OperationId", $operationId)

        # Start async execution
        $asyncResult = $powershell.BeginInvoke()

        # Create operation context WITHOUT TIMER
        $operationContext = @{
            OperationId = $operationId
            OperationName = $OperationName
            PowerShell = $powershell
            AsyncResult = $asyncResult
            RunspacePool = $runspacePool
            ProgressCallback = $ProgressCallback
            CompletedCallback = $CompletedCallback
            StartTime = Get-Date
            TimeoutTime = (Get-Date).AddSeconds($TimeoutSeconds)
            AllowCancel = $AllowCancel
            IsCancelled = $false
            IsCompleted = $false
        }

        # Store operation in global tracking
        $global:AsyncOperations[$operationId] = $operationContext

        # Start monitoring job instead of timer (safer approach)
        Start-Job -ScriptBlock {
            param($OperationId, $TimeoutSeconds)

            $checkInterval = 1000 # 1 second
            $maxWait = $TimeoutSeconds * 1000
            $elapsed = 0

            while ($elapsed -lt $maxWait) {
                Start-Sleep -Milliseconds $checkInterval
                $elapsed += $checkInterval

                # Check if operation exists and is completed
                if ($global:AsyncOperations -and $global:AsyncOperations.ContainsKey($OperationId)) {
                    $context = $global:AsyncOperations[$OperationId]
                    if ($context.AsyncResult.IsCompleted -or $context.IsCompleted) {
                        # Signal completion
                        return @{ Status = "Completed"; OperationId = $OperationId }
                    }
                } else {
                    # Operation no longer exists
                    return @{ Status = "NotFound"; OperationId = $OperationId }
                }
            }

            # Timeout reached
            return @{ Status = "Timeout"; OperationId = $OperationId }

        } -ArgumentList $operationId, $TimeoutSeconds | Out-Null

        Write-Logger "Async operation started: $OperationName (ID: $operationId)" "SUCCESS" -Category "AsyncOps"
        Set-WDCAStatus "Running $OperationName..."

        # Start completion checker in background
        Start-Job -ScriptBlock {
            param($OperationId)

            # Wait for operation to complete
            while ($true) {
                Start-Sleep -Milliseconds 500

                if ($global:AsyncOperations -and $global:AsyncOperations.ContainsKey($OperationId)) {
                    $context = $global:AsyncOperations[$OperationId]

                    if ($context.AsyncResult.IsCompleted -and -not $context.IsCompleted) {
                        # Operation completed, trigger completion
                        try {
                            Complete-AsyncOperation -OperationId $OperationId
                        } catch {
                            Write-Host "Error in completion handler: $($_.Exception.Message)" -ForegroundColor Red
                        }
                        break
                    }

                    if ($context.IsCompleted -or $context.IsCancelled) {
                        break
                    }
                } else {
                    break
                }
            }
        } -ArgumentList $operationId | Out-Null

        return $operationId

    }
    catch {
        Write-Logger "Failed to start async operation: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
        throw
    }
}

function Complete-AsyncOperation {
    <#
    .SYNOPSIS
        Completes an async operation and handles cleanup
    #>

    param([string]$OperationId)

    try {
        if (-not $global:AsyncOperations -or -not $global:AsyncOperations.ContainsKey($OperationId)) {
            return
        }

        $context = $global:AsyncOperations[$OperationId]
        if ($context.IsCompleted) {
            return
        }

        # Mark as completed to prevent double execution
        $context.IsCompleted = $true

        # Get results
        try {
            $result = $context.PowerShell.EndInvoke($context.AsyncResult)
            $context.PowerShell.Dispose()
        } catch {
            Write-Logger "Error getting async result: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
            $result = @{ Success = $false; Error = @{ Message = $_.Exception.Message } }
        }

        $duration = ((Get-Date) - $context.StartTime).TotalSeconds

        if ($result -and $result.Success) {
            Write-Logger "$($context.OperationName) completed successfully in $([math]::Round($duration, 2))s" "SUCCESS" -Category "AsyncOps"

            # Execute completion callback on UI thread
            if ($context.CompletedCallback -and $global:sync.Form) {
                try {
                    $global:sync.Form.Dispatcher.Invoke([System.Action]{
                        try {
                            & $context.CompletedCallback $result.Result
                        } catch {
                            Write-Logger "Completion callback failed: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
                        }
                    }, [System.Windows.Threading.DispatcherPriority]::Normal)
                } catch {
                    Write-Logger "Failed to invoke completion callback: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
                }
            }
        }
        else {
            $errorMsg = if ($result -and $result.Error) { $result.Error.Message } else { "Unknown error occurred" }
            Write-Logger "$($context.OperationName) failed: $errorMsg" "ERROR" -Category "AsyncOps"

            # Show error to user on UI thread
            if ($global:sync.Form) {
                try {
                    $global:sync.Form.Dispatcher.Invoke([System.Action]{
                        [System.Windows.MessageBox]::Show(
                            "Operation failed: $errorMsg",
                            "WDCA - Operation Failed",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }, [System.Windows.Threading.DispatcherPriority]::Normal)
                } catch {
                    Write-Logger "Failed to show error dialog: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
                }
            }
        }

        # Cleanup
        Cleanup-AsyncOperation -OperationId $OperationId

    }
    catch {
        Write-Logger "Error completing async operation $OperationId`: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
        Cleanup-AsyncOperation -OperationId $OperationId
    }
}

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

function Get-RunspacePool {
    <#
    .SYNOPSIS
        Gets or creates the global runspace pool
    #>

    if (-not $global:RunspacePool -or $global:RunspacePool.RunspacePoolStateInfo.State -ne 'Opened') {
        try {
            # Determine optimal thread count
            $maxThreads = [math]::Min([Environment]::ProcessorCount * 2, 8)
            $minThreads = [math]::Max([Environment]::ProcessorCount, 2)

            Write-Logger "Initializing runspace pool with $minThreads-$maxThreads threads" "INFO" -Category "AsyncOps"

            # Create initial session state with required modules and variables
            $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

            # Add sync variable to session state
            if ($global:sync) {
                $syncVariable = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('sync', $global:sync, $null)
                $initialSessionState.Variables.Add($syncVariable)
            }

            # Create runspace pool
            $global:RunspacePool = [runspacefactory]::CreateRunspacePool(
                $minThreads,
                $maxThreads,
                $initialSessionState,
                $Host
            )

            $global:RunspacePool.Open()
        }
        catch {
            Write-Logger "Failed to initialize runspace pool: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
            throw
        }
    }

    return $global:RunspacePool
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
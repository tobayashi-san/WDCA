function Start-AsyncOperation {
    <#
    .SYNOPSIS
        Enhanced async operation manager with improved error handling and monitoring

    .PARAMETER ScriptBlock
        The script block to execute asynchronously

    .PARAMETER ProgressCallback
        Callback for progress updates

    .PARAMETER CompletedCallback
        Callback when operation completes

    .PARAMETER OperationName
        Name of the operation for tracking and logging

    .PARAMETER TimeoutSeconds
        Maximum time to wait for operation completion (default: 3600 seconds)

    .PARAMETER AllowCancel
        Whether the operation can be cancelled by user (default: true)

    .EXAMPLE
        Start-AsyncOperation -ScriptBlock { Get-Process } -OperationName "Process List" -CompletedCallback { param($result) Write-Host $result.Count }
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

        # Save current UI state
        Save-UIState

        # Disable UI elements
        Set-UIEnabled -Enabled $false

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
                MemoryUsed = 0
                CpuTime = 0
            }

            try {
                # Capture initial performance metrics
                $process = Get-Process -Id $PID
                $initialMemory = $process.WorkingSet64
                $initialCpuTime = $process.TotalProcessorTime

                Write-Verbose "Executing async operation: $OperationName"

                # Execute the actual work
                $result.Result = Invoke-Command -ScriptBlock $ScriptBlock
                $result.Success = $true

                # Capture final performance metrics
                $process = Get-Process -Id $PID
                $result.MemoryUsed = [math]::Round(($process.WorkingSet64 - $initialMemory) / 1MB, 2)
                $result.CpuTime = ($process.TotalProcessorTime - $initialCpuTime).TotalSeconds

                Write-Verbose "Async operation completed successfully: $OperationName"
            }
            catch {
                $result.Error = @{
                    Message = $_.Exception.Message
                    FullError = $_.Exception.ToString()
                    ScriptStackTrace = $_.ScriptStackTrace
                    CategoryInfo = $_.CategoryInfo.ToString()
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

        # Create operation context
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
            Timer = $null
        }

        # Store operation in global tracking
        $global:AsyncOperations[$operationId] = $operationContext

        # Create monitoring timer
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(250)
        $operationContext.Timer = $timer

        # Timer tick event for monitoring
        $timer.Add_Tick({
            try {
                $context = $global:AsyncOperations[$operationId]
                if (-not $context -or $context.IsCompleted) {
                    return
                }

                $currentTime = Get-Date

                # Check for timeout
                if ($currentTime -gt $context.TimeoutTime) {
                    Write-Logger "Operation timed out: $($context.OperationName)" "WARNING" -Category "AsyncOps"
                    Stop-AsyncOperation -OperationId $operationId -Reason "Timeout"
                    return
                }

                # Check if operation is complete
                if ($context.AsyncResult.IsCompleted) {
                    Complete-AsyncOperation -OperationId $operationId
                    return
                }

                # Execute progress callback if provided
                if ($context.ProgressCallback) {
                    try {
                        $elapsed = ($currentTime - $context.StartTime).TotalSeconds
                        & $context.ProgressCallback $elapsed
                    }
                    catch {
                        Write-Logger "Progress callback failed for $($context.OperationName): $($_.Exception.Message)" "WARNING" -Category "AsyncOps"
                    }
                }

                # Update progress indicator
                $elapsed = [math]::Round(($currentTime - $context.StartTime).TotalSeconds)
                Update-ProgressSafe -Message "Running $($context.OperationName)... (${elapsed}s)" -PercentComplete -1

            }
            catch {
                Write-Logger "Timer tick error for operation $operationId`: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
                Stop-AsyncOperation -OperationId $operationId -Reason "Timer Error"
            }
        })

        # Start monitoring timer
        $timer.Start()

        Write-Logger "Async operation started: $OperationName (ID: $operationId)" "SUCCESS" -Category "AsyncOps"
        Set-WDCAStatus "Running $OperationName..."

        return $operationId

    }
    catch {
        Write-Logger "Failed to start async operation: $($_.Exception.Message)" "ERROR" -Category "AsyncOps"

        # Restore UI state on failure
        Restore-UIState
        Reset-ProgressBar

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
        $context = $global:AsyncOperations[$OperationId]
        if (-not $context -or $context.IsCompleted) {
            return
        }

        # Mark as completed to prevent double execution
        $context.IsCompleted = $true

        # Stop and cleanup timer
        if ($context.Timer) {
            $context.Timer.Stop()
            $context.Timer = $null
        }

        # Get results
        $result = $context.PowerShell.EndInvoke($context.AsyncResult)
        $context.PowerShell.Dispose()

        $duration = ((Get-Date) - $context.StartTime).TotalSeconds

        if ($result -and $result.Success) {
            Write-Logger "$($context.OperationName) completed successfully in $([math]::Round($duration, 2))s" "SUCCESS" -Category "AsyncOps"

            # Log performance metrics if available
            if ($result.MemoryUsed -ne 0 -or $result.CpuTime -ne 0) {
                Write-Logger "Performance: Memory: $($result.MemoryUsed)MB, CPU: $($result.CpuTime)s" "TRACE" -Category "Performance"
            }

            # Execute completion callback
            if ($context.CompletedCallback) {
                try {
                    & $context.CompletedCallback $result.Result
                }
                catch {
                    Write-Logger "Completion callback failed for $($context.OperationName): $($_.Exception.Message)" "ERROR" -Category "AsyncOps"
                    Show-ErrorDialog -Title "Operation Completed with Errors" -Message "The operation completed but there was an error processing the results: $($_.Exception.Message)"
                }
            }
        }
        else {
            $errorMsg = if ($result.Error) { $result.Error.Message } else { "Unknown error occurred" }
            Write-Logger "$($context.OperationName) failed: $errorMsg" "ERROR" -Category "AsyncOps"

            # Log detailed error information
            if ($result.Error -and $result.Error.FullError) {
                Write-Logger "Detailed error: $($result.Error.FullError)" "DEBUG" -Category "AsyncOps"
            }

            # Show error to user
            Show-ErrorDialog -Title "Operation Failed" -Message "Operation failed: $errorMsg"
        }

        # Cleanup and restore UI
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
        $context = $global:AsyncOperations[$OperationId]
        if (-not $context) {
            return
        }

        Write-Logger "Stopping async operation: $($context.OperationName) - Reason: $Reason" "WARNING" -Category "AsyncOps"

        $context.IsCancelled = $true
        $context.IsCompleted = $true

        # Stop timer
        if ($context.Timer) {
            $context.Timer.Stop()
            $context.Timer = $null
        }

        # Stop PowerShell execution
        if ($context.PowerShell -and -not $context.AsyncResult.IsCompleted) {
            try {
                $context.PowerShell.Stop()
                # Give it a moment to stop gracefully
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
        $context = $global:AsyncOperations[$OperationId]
        if ($context) {
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
        if ($global:AsyncOperations.Count -eq 0) {
            # Restore UI state
            Restore-UIState
            Reset-ProgressBar
            Set-WDCAStatus "Ready"

            # Trigger garbage collection to clean up resources
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
            $syncVariable = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('sync', $global:sync, $null)
            $initialSessionState.Variables.Add($syncVariable)

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
        $operationIds = $global:AsyncOperations.Keys | ForEach-Object { $_ }

        foreach ($operationId in $operationIds) {
            Stop-AsyncOperation -OperationId $operationId -Reason "Application Shutdown"
        }

        # Force cleanup if anything remains
        $global:AsyncOperations.Clear()

        # Restore UI
        Restore-UIState
        Reset-ProgressBar

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
    foreach ($context in $global:AsyncOperations.Values) {
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
    }

    return $activeOps
}

function Show-ErrorDialog {
    <#
    .SYNOPSIS
        Shows an error dialog to the user
    #>

    param(
        [string]$Title = "Error",
        [string]$Message
    )

    try {
        if ($global:sync.Form) {
            $global:sync.Form.Dispatcher.Invoke([System.Action]{
                [System.Windows.MessageBox]::Show(
                    $Message,
                    "WDCA - $Title",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            })
        }
        else {
            Write-Host "ERROR: $Message" -ForegroundColor Red
        }
    }
    catch {
        Write-Logger "Failed to show error dialog: $($_.Exception.Message)" "ERROR" -Category "UI"
    }
}
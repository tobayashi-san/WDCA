function Write-Logger {
    <#
    .SYNOPSIS
        Advanced logging function for WDCA with enhanced features

    .DESCRIPTION
        Centralized logging function that supports multiple log levels, colored console output,
        file logging with timestamps, and thread-safe operations

    .PARAMETER Message
        The message to log

    .PARAMETER Level
        Log level (INFO, WARNING, ERROR, DEBUG, SUCCESS, TRACE)

    .PARAMETER WriteToConsole
        Whether to write to console (default: true)

    .PARAMETER WriteToFile
        Whether to write to log file (default: true)

    .PARAMETER Category
        Optional category for the log entry

    .PARAMETER Source
        Optional source component that generated the log

    .EXAMPLE
        Write-Logger "Application installation started" "INFO"
        Write-Logger "Failed to install application" "ERROR" -Category "Installation"
        Write-Logger "Debug information" "DEBUG" -Source "NetworkConfig"
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS", "TRACE")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $false)]
        [bool]$WriteToConsole = $true,

        [Parameter(Mandatory = $false)]
        [bool]$WriteToFile = $true,

        [Parameter(Mandatory = $false)]
        [string]$Category = "",

        [Parameter(Mandatory = $false)]
        [string]$Source = ""
    )

    begin {
        # Initialize if not already done
        if (-not $global:sync) {
            $global:sync = @{}
        }

        if (-not $global:sync.LoggingInitialized) {
            Initialize-Logging
        }
    }

    process {
        try {
            # Create timestamp
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"

            # Build log entry components
            $logComponents = @()
            $logComponents += "[$timestamp]"
            $logComponents += "[$Level]"

            if ($Source) {
                $logComponents += "[$Source]"
            }

            if ($Category) {
                $logComponents += "[$Category]"
            }

            $logComponents += $Message

            # Construct full log entry
            $logEntry = $logComponents -join " "

            # Write to console with colors if enabled
            if ($WriteToConsole) {
                Write-ConsoleWithColor -LogEntry $logEntry -Level $Level -Message $Message
            }

            # Write to file if enabled and available
            if ($WriteToFile -and $global:sync.logFile) {
                Write-LogToFile -LogEntry $logEntry
            }

            # Update UI status if available (thread-safe)
            if ($global:sync.WPFStatusText -and $Level -ne "DEBUG" -and $Level -ne "TRACE") {
                Update-StatusBarSafe -Message $Message
            }

            # Handle error level logging
            if ($Level -eq "ERROR") {
                Handle-ErrorLogging -Message $Message -Source $Source -Category $Category
            }

            # Performance monitoring for trace level
            if ($Level -eq "TRACE" -and $global:sync.Debug) {
                Monitor-Performance -Message $Message
            }

        }
        catch {
            # Fallback logging if main logging fails
            try {
                $fallbackMessage = "[$timestamp] [ERROR] [Logger] Logging failed: $($_.Exception.Message). Original: $Message"
                Write-Host $fallbackMessage -ForegroundColor Red

                if ($global:sync.logFile) {
                    Add-Content -Path $global:sync.logFile -Value $fallbackMessage -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Ultimate fallback - just write to host
                Write-Host "Critical logging failure - Original message: $Message" -ForegroundColor Red
            }
        }
    }
}

function Initialize-Logging {
    <#
    .SYNOPSIS
        Initializes the logging system
    #>

    try {
        # Set up log rotation if file gets too large (50MB limit)
        if ($global:sync.logFile -and (Test-Path $global:sync.logFile)) {
            $logSize = (Get-Item $global:sync.logFile).Length / 1MB
            if ($logSize -gt 50) {
                $backupLog = $global:sync.logFile -replace '\.log$', "_backup_$(Get-Date -Format 'yyyyMMdd').log"
                Move-Item -Path $global:sync.logFile -Destination $backupLog -Force -ErrorAction SilentlyContinue
            }
        }

        # Initialize performance counters
        $global:sync.LoggingStats = @{
            TotalMessages = 0
            ErrorCount = 0
            WarningCount = 0
            StartTime = Get-Date
        }

        # Set up log levels based on configuration
        $global:sync.LogLevels = @{
            "TRACE" = 0
            "DEBUG" = 1
            "INFO" = 2
            "SUCCESS" = 2
            "WARNING" = 3
            "ERROR" = 4
        }

        $global:sync.CurrentLogLevel = if ($global:sync.Debug) { 0 } else { 2 }
        $global:sync.LoggingInitialized = $true

        # Create log directory if it doesn't exist
        if ($global:sync.logFile) {
            $logDir = Split-Path $global:sync.logFile -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
        }

        Write-Host "Logging system initialized" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to initialize logging: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Write-ConsoleWithColor {
    <#
    .SYNOPSIS
        Writes colored output to console based on log level
    #>

    param(
        [string]$LogEntry,
        [string]$Level,
        [string]$Message
    )

    try {
        # Check if we should display this level
        if ($global:sync.LogLevels -and $global:sync.LogLevels.ContainsKey($Level) -and $global:sync.CurrentLogLevel) {
            if ($global:sync.LogLevels[$Level] -lt $global:sync.CurrentLogLevel) {
                return
            }
        }

        $color = switch ($Level) {
            "SUCCESS" { "Green" }
            "INFO" { "White" }
            "WARNING" { "Yellow" }
            "ERROR" { "Red" }
            "DEBUG" { "Cyan" }
            "TRACE" { "DarkGray" }
            default { "White" }
        }

        # Add timestamp for better readability in console
        $consoleMessage = if ($Level -eq "DEBUG" -or $Level -eq "TRACE") {
            $LogEntry
        } else {
            "$(Get-Date -Format 'HH:mm:ss') [$Level] $Message"
        }

        Write-Host $consoleMessage -ForegroundColor $color

        # Update statistics
        if ($global:sync.LoggingStats) {
            $global:sync.LoggingStats.TotalMessages++
            if ($Level -eq "ERROR") { $global:sync.LoggingStats.ErrorCount++ }
            if ($Level -eq "WARNING") { $global:sync.LoggingStats.WarningCount++ }
        }
    }
    catch {
        # Fallback to basic write-host
        Write-Host "$Level`: $Message" -ForegroundColor White
    }
}

function Write-LogToFile {
    <#
    .SYNOPSIS
        Thread-safe file logging
    #>

    param([string]$LogEntry)

    try {
        # Simple file append with retry logic
        $retryCount = 0
        $maxRetries = 3

        do {
            try {
                Add-Content -Path $global:sync.logFile -Value $LogEntry -Encoding UTF8 -ErrorAction Stop
                break
            }
            catch {
                $retryCount++
                if ($retryCount -ge $maxRetries) {
                    # Give up after max retries
                    break
                }
                Start-Sleep -Milliseconds (100 * $retryCount)
            }
        } while ($retryCount -lt $maxRetries)
    }
    catch {
        # Silent fail for file logging to prevent recursive errors
    }
}

function Update-StatusBarSafe {
    <#
    .SYNOPSIS
        Thread-safe status bar updates
    #>

    param([string]$Message)

    try {
        if ($global:sync.WPFStatusText -and $global:sync.Form) {
            $global:sync.Form.Dispatcher.Invoke([System.Action]{
                $global:sync.WPFStatusText.Text = $Message
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    }
    catch {
        # Ignore status bar update errors
    }
}

function Handle-ErrorLogging {
    <#
    .SYNOPSIS
        Special handling for error-level logs
    #>

    param(
        [string]$Message,
        [string]$Source,
        [string]$Category
    )

    try {
        # Store error in error collection for later analysis
        if (-not $global:sync.ErrorLog) {
            $global:sync.ErrorLog = [System.Collections.Generic.List[PSObject]]::new()
        }

        $errorEntry = [PSCustomObject]@{
            Timestamp = Get-Date
            Message = $Message
            Source = $Source
            Category = $Category
            StackTrace = $null
        }

        # Try to get stack trace safely
        try {
            $stackTrace = Get-PSCallStack | Select-Object -Skip 2 | Select-Object -First 3
            $errorEntry.StackTrace = $stackTrace
        }
        catch {
            # If stack trace fails, just continue
        }

        $global:sync.ErrorLog.Add($errorEntry)

        # Keep only last 100 errors to prevent memory issues
        if ($global:sync.ErrorLog.Count -gt 100) {
            $global:sync.ErrorLog.RemoveAt(0)
        }

        # Trigger error notification if UI is available
        if ($global:sync.Form -and $global:sync.ShowErrorNotifications) {
            Show-ErrorNotification -Message $Message
        }
    }
    catch {
        # Don't fail if error handling fails
    }
}

function Monitor-Performance {
    <#
    .SYNOPSIS
        Performance monitoring for trace-level logging
    #>

    param([string]$Message)

    try {
        if (-not $global:sync.PerformanceCounters) {
            $global:sync.PerformanceCounters = @{}
        }

        $process = Get-Process -Id $PID -ErrorAction SilentlyContinue
        if ($process) {
            $memoryUsage = [math]::Round($process.WorkingSet64 / 1MB, 2)
            $cpuTime = $process.TotalProcessorTime.TotalSeconds

            $perfData = "[PERF] Memory: ${memoryUsage}MB, CPU: ${cpuTime}s - $Message"

            if ($global:sync.logFile) {
                Add-Content -Path $global:sync.logFile -Value $perfData -Encoding UTF8 -ErrorAction SilentlyContinue
            }

            # Alert if memory usage is high
            if ($memoryUsage -gt 500) {
                Write-Logger "High memory usage detected: ${memoryUsage}MB" "WARNING" -Category "Performance"
            }
        }
    }
    catch {
        # Don't fail if performance monitoring fails
    }
}

function Show-ErrorNotification {
    <#
    .SYNOPSIS
        Shows error notifications in UI
    #>

    param([string]$Message)

    try {
        if ($global:sync.Form) {
            $global:sync.Form.Dispatcher.Invoke([System.Action]{
                # Create a simple error indicator
                if ($global:sync.ErrorIndicator) {
                    $global:sync.ErrorIndicator.Visibility = "Visible"
                    $global:sync.ErrorIndicator.ToolTip = "Recent error: $Message"
                }
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    }
    catch {
        # Ignore notification errors
    }
}

function Get-LoggingStatistics {
    <#
    .SYNOPSIS
        Returns current logging statistics
    #>

    if (-not $global:sync.LoggingStats) {
        return @{
            TotalMessages = 0
            ErrorCount = 0
            WarningCount = 0
            Uptime = "0:00:00"
        }
    }

    $uptime = (Get-Date) - $global:sync.LoggingStats.StartTime

    return @{
        TotalMessages = $global:sync.LoggingStats.TotalMessages
        ErrorCount = $global:sync.LoggingStats.ErrorCount
        WarningCount = $global:sync.LoggingStats.WarningCount
        Uptime = $uptime.ToString("h\:mm\:ss")
        LogFile = $global:sync.logFile
        CurrentLevel = $global:sync.CurrentLogLevel
    }
}

function Export-LoggingReport {
    <#
    .SYNOPSIS
        Exports a comprehensive logging report
    #>

    param(
        [string]$OutputPath = "$env:USERPROFILE\Desktop\WDCA_LogReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    )

    try {
        $stats = Get-LoggingStatistics
        $report = @"
WDCA Logging Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
================================================================================

STATISTICS:
- Total Messages Logged: $($stats.TotalMessages)
- Errors: $($stats.ErrorCount)
- Warnings: $($stats.WarningCount)
- Session Uptime: $($stats.Uptime)
- Log File: $($stats.LogFile)
- Current Log Level: $($stats.CurrentLevel)

RECENT ERRORS:
"@

        if ($global:sync.ErrorLog -and $global:sync.ErrorLog.Count -gt 0) {
            foreach ($error in ($global:sync.ErrorLog | Select-Object -Last 10)) {
                $report += "`n[$($error.Timestamp.ToString('HH:mm:ss'))] $($error.Source): $($error.Message)"
            }
        } else {
            $report += "`nNo recent errors recorded."
        }

        $report += "`n`n================================================================================`n"

        Set-Content -Path $OutputPath -Value $report -Encoding UTF8
        Write-Logger "Logging report exported to: $OutputPath" "SUCCESS"

        return $OutputPath
    }
    catch {
        Write-Logger "Failed to export logging report: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Alias for compatibility
function Set-WDCAStatus {
    <#
    .SYNOPSIS
        Updates the WDCA status bar - wrapper for Write-Logger
    #>

    param([string]$Status)

    if ($global:sync.WPFStatusText) {
        Update-StatusBarSafe -Message $Status
    }

    Write-Logger $Status "INFO" $false
}
function Write-Logger {
    param(
        [string]$Message,
        [ValidateSet("TRACE","DEBUG","INFO","SUCCESS","WARNING","ERROR")]
        [string]$Level = "INFO",
        [string]$Category = ""
    )

    if (-not $script:sync.LoggingInitialized) { Initialize-Logging }

    try {
        # Level-Filter prüfen
        if ($script:sync.LogLevels[$Level] -lt $script:sync.CurrentLogLevel) {
            return
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $prefix    = if ($Category) { "[$Category]" } else { "" }
        $logLine   = "$timestamp [$Level] $prefix $Message"

        # Konsolen-Ausgabe
        $color = switch ($Level) {
            "SUCCESS" { "Green" }
            "INFO"    { "White" }
            "WARNING" { "Yellow" }
            "ERROR"   { "Red" }
            "DEBUG"   { "Cyan" }
            "TRACE"   { "DarkGray" }
        }
        Write-Host $logLine -ForegroundColor $color

        # File-Log
        if ($script:sync.logFile) {
            Write-LogToFile $logLine
        }

        # Status-Bar
        if ($script:sync.WPFStatusText -and $Level -notin @("DEBUG","TRACE")) {
            Update-StatusBarSafe -Message $Message
        }

        # Statistik
        $script:sync.LoggingStats.TotalMessages++
        if ($Level -eq "ERROR")   { $script:sync.LoggingStats.ErrorCount++ }
        if ($Level -eq "WARNING") { $script:sync.LoggingStats.WarningCount++ }

        # Spezielle Error-Behandlung
        if ($Level -eq "ERROR") {
            Handle-ErrorLogging -Message $Message -Source "WDCA" -Category $Category
        }
    }
    catch {
        Write-Host "Logging failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Initialize-Logging {
    try {
        # Rotation bei >50MB
        if ($script:sync.logFile -and (Test-Path $script:sync.logFile)) {
            $logSize = (Get-Item $script:sync.logFile).Length / 1MB
            if ($logSize -gt 50) {
                $backupLog = $script:sync.logFile -replace '\.log$', "_backup_$(Get-Date -Format 'yyyyMMdd').log"
                Move-Item -Path $script:sync.logFile -Destination $backupLog -Force -ErrorAction SilentlyContinue
            }
        }

        $script:sync.LoggingStats = @{
            TotalMessages = 0
            ErrorCount    = 0
            WarningCount  = 0
            StartTime     = Get-Date
        }

        $script:sync.LogLevels = @{
            "TRACE"   = 0
            "DEBUG"   = 1
            "INFO"    = 2
            "SUCCESS" = 2
            "WARNING" = 3
            "ERROR"   = 4
        }

        $script:sync.CurrentLogLevel = if ($script:sync.Debug) { 0 } else { 2 }
        $script:sync.LoggingInitialized = $true

        if ($script:sync.logFile) {
            $logDir = Split-Path $script:sync.logFile -Parent
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
    param([string]$LogEntry)

    $retryCount = 0
    $maxRetries = 3
    do {
        try {
            Add-Content -Path $script:sync.logFile -Value $LogEntry -Encoding UTF8 -ErrorAction Stop
            break
        }
        catch {
            $retryCount++
            Start-Sleep -Milliseconds (100 * $retryCount)
        }
    } while ($retryCount -lt $maxRetries)
}

function Update-StatusBarSafe {
    param([string]$Message)

    try {
        if ($script:sync.WPFStatusText -and $script:sync.Form) {
            $script:sync.Form.Dispatcher.Invoke([System.Action]{
                $script:sync.WPFStatusText.Text = $Message
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    } catch {}
}

function Handle-ErrorLogging {
    param(
        [string]$Message,
        [string]$Source,
        [string]$Category
    )

    if (-not $script:sync.ErrorLog) {
        $script:sync.ErrorLog = [System.Collections.Generic.List[PSObject]]::new()
    }

    $entry = [PSCustomObject]@{
        Timestamp  = Get-Date
        Message    = $Message
        Source     = $Source
        Category   = $Category
        StackTrace = ($callstack = Get-PSCallStack | Select-Object -Skip 2 -First 3 | Out-String)
    }

    $script:sync.ErrorLog.Add($entry)

    if ($script:sync.ErrorLog.Count -gt 100) {
        $script:sync.ErrorLog.RemoveAt(0)
    }

    if ($script:sync.Form -and $script:sync.ShowErrorNotifications) {
        Show-ErrorNotification -Message $Message
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
    param([string]$Message)

    try {
        if ($script:sync.Form -and $script:sync.ErrorIndicator) {
            $script:sync.Form.Dispatcher.Invoke([System.Action]{
                $script:sync.ErrorIndicator.Visibility = "Visible"
                $script:sync.ErrorIndicator.ToolTip    = "Recent error: $Message"
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    } catch {}
}

function Set-WDCAStatus {
    <#
    .SYNOPSIS
        Updates the WDCA status bar

    .DESCRIPTION
        Convenience function to update the status bar text

    .PARAMETER Status
        The status message to display

    .EXAMPLE
        Set-WDCAStatus "Ready for operations"
    #>

    param([string]$Status)

    if ($global:sync.WPFStatusText) {
        $global:sync.WPFStatusText.Dispatcher.Invoke([action]{
            $global:sync.WPFStatusText.Text = $Status
        })
    }

    Write-Logger $Status "INFO" $false
}
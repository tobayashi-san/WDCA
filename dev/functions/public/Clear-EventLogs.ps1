function Clear-EventLogs {
    <#
    .SYNOPSIS
        Clears Windows Event Logs

    .DESCRIPTION
        Clears all event logs to reduce system footprint for imaging
    #>

    try {
        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 }
        $clearedCount = 0

        foreach ($log in $logs) {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
                $clearedCount++
            }
            catch {
                # Some logs cannot be cleared, continue with others
            }
        }

        Write-Logger "Cleared $clearedCount event logs" "INFO"
        return "$clearedCount logs cleared"
    }
    catch {
        Write-Logger "Error clearing event logs: $($_.Exception.Message)" "WARNING"
        return "Error clearing logs"
    }
}

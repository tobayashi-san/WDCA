# Runspace Pool Management
function Initialize-RunspacePool {
    <#
    .SYNOPSIS
        Initialisiert den Runspace Pool fÃ¼r bessere Performance
    #>

    if (-not $global:RunspacePool) {
        try {
            $global:RunspacePool = [runspacefactory]::CreateRunspacePool(1, 5)
            $global:RunspacePool.Open()
            Write-Logger "Runspace pool initialized with 1-5 threads" "INFO"
        }
        catch {
            Write-Logger "Error initializing runspace pool: $($_.Exception.Message)" "ERROR"
        }
    }
}

function Close-RunspacePool {
    <#
    .SYNOPSIS
        SchlieÃŸt den Runspace Pool beim Beenden
    #>

    if ($global:RunspacePool) {
        try {
            $global:RunspacePool.Close()
            $global:RunspacePool.Dispose()
            $global:RunspacePool = $null
            Write-Logger "Runspace pool closed" "INFO"
        }
        catch {
            Write-Logger "Error closing runspace pool: $($_.Exception.Message)" "ERROR"
        }
    }
}

# Job Management fÃ¼r langanhaltende Operationen
function Get-ActiveAsyncOperations {
    <#
    .SYNOPSIS
        Zeigt aktive async Operationen an
    #>

    if ($global:ActiveOperations) {
        return $global:ActiveOperations.Keys
    }
    return @()
}


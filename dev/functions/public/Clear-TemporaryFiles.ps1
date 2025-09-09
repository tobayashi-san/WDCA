function Clear-TemporaryFiles {
    <#
    .SYNOPSIS
        Clears temporary files from various locations with improved error handling
    #>

    $totalCleaned = 0
    $locations = @(
        @{Path = "$env:TEMP"; Name = "User Temp"},
        @{Path = "$env:SystemRoot\Temp"; Name = "System Temp"},
        @{Path = "$env:LocalAppData\Temp"; Name = "Local AppData Temp"}
    )

    foreach ($location in $locations) {
        if (-not (Test-Path $location.Path)) {
            Write-Logger "Location not found: $($location.Path)" "WARNING"
            continue
        }

        try {
            $sizeBefore = 0
            $files = Get-ChildItem -Path $location.Path -Recurse -File -ErrorAction SilentlyContinue
            if ($files) {
                $sizeBefore = ($files | Measure-Object -Property Length -Sum).Sum
            }

            # Remove files with better error handling
            $removed = 0
            foreach ($file in $files) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $removed++
                }
                catch {
                    Write-Logger "Could not remove file: $($file.FullName) - $($_.Exception.Message)" "DEBUG"
                }
            }

            $sizeAfter = 0
            $remainingFiles = Get-ChildItem -Path $location.Path -Recurse -File -ErrorAction SilentlyContinue
            if ($remainingFiles) {
                $sizeAfter = ($remainingFiles | Measure-Object -Property Length -Sum).Sum
            }

            $cleaned = $sizeBefore - $sizeAfter
            $totalCleaned += $cleaned

            Write-Logger "Cleaned $($location.Name) - Removed $removed files, Freed $([math]::Round($cleaned / 1MB, 2)) MB" "INFO"
        }
        catch {
            Write-Logger "Error cleaning $($location.Name): $($_.Exception.Message)" "ERROR"
        }
    }

    return "$([math]::Round($totalCleaned / 1MB, 2)) MB cleaned"
}
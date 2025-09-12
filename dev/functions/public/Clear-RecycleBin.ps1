function Clear-WDCARecycleBin {
    <#
    .SYNOPSIS
        Empties the Recycle Bin safely without any loops or self-calls

    .DESCRIPTION
        Clears all files from the Recycle Bin using safe methods - renamed to avoid conflicts
    #>

    try {
        Write-Logger "Starting WDCA recycle bin cleanup" "INFO"

        $totalSize = 0
        $totalFiles = 0
        $success = $false

        # Method 1: Use Windows Shell COM object (safest approach)
        Write-Logger "Attempting COM Shell method" "INFO"

        $comShell = $null
        try {
            $comShell = New-Object -ComObject Shell.Application -ErrorAction Stop
            $recycleBinNamespace = $comShell.Namespace(0xA)  # Recycle Bin namespace

            if ($recycleBinNamespace) {
                $recycleBinItems = $recycleBinNamespace.Items()

                if ($recycleBinItems -and $recycleBinItems.Count -gt 0) {
                    $totalFiles = $recycleBinItems.Count
                    Write-Logger "Found $totalFiles items in recycle bin" "INFO"

                    # Empty the recycle bin
                    $recycleBinNamespace.InvokeVerb("Empty")
                    Start-Sleep -Seconds 2  # Give it time to complete

                    Write-Logger "Recycle bin emptied via COM Shell method" "SUCCESS"
                    $success = $true
                    return "Recycle bin emptied: $totalFiles items removed"
                }
                else {
                    Write-Logger "Recycle bin is already empty" "INFO"
                    return "Recycle bin was already empty"
                }
            }
        }
        catch {
            Write-Logger "COM Shell method failed: $($_.Exception.Message)" "WARNING"
        }
        finally {
            if ($comShell) {
                try {
                    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($comShell) | Out-Null
                }
                catch { }
                $comShell = $null
            }
        }

        # Method 2: Use rundll32 system call if COM failed
        if (-not $success) {
            Write-Logger "Attempting rundll32 method" "INFO"
            try {
                $processInfo = Start-Process -FilePath "rundll32.exe" -ArgumentList "shell32.dll,SHEmptyRecycleBinW" -Wait -PassThru -NoNewWindow -ErrorAction Stop

                if ($processInfo.ExitCode -eq 0) {
                    Write-Logger "Recycle bin emptied via rundll32 method" "SUCCESS"
                    $success = $true
                    return "Recycle bin emptied successfully (rundll32)"
                }
                else {
                    Write-Logger "rundll32 returned exit code: $($processInfo.ExitCode)" "WARNING"
                }
            }
            catch {
                Write-Logger "rundll32 method failed: $($_.Exception.Message)" "WARNING"
            }
        }

        # Method 3: Use PowerShell cmdlet as last resort (if available)
        if (-not $success) {
            $clearRecycleBinCmd = Get-Command -Name "Microsoft.PowerShell.Management\Clear-RecycleBin" -ErrorAction SilentlyContinue
            if ($clearRecycleBinCmd) {
                Write-Logger "Attempting PowerShell cmdlet method" "INFO"
                try {
                    & $clearRecycleBinCmd -Force -ErrorAction Stop
                    Write-Logger "Recycle bin emptied via PowerShell cmdlet" "SUCCESS"
                    $success = $true
                    return "Recycle bin emptied successfully (PowerShell cmdlet)"
                }
                catch {
                    Write-Logger "PowerShell cmdlet method failed: $($_.Exception.Message)" "WARNING"
                }
            }
        }

        # If all methods failed
        if (-not $success) {
            Write-Logger "All recycle bin clearing methods failed" "WARNING"
            return "Could not empty recycle bin - manual intervention may be required"
        }
    }
    catch {
        Write-Logger "Critical error in WDCA recycle bin cleanup: $($_.Exception.Message)" "ERROR"
        return "Error emptying recycle bin: $($_.Exception.Message)"
    }
}

# Legacy function name for compatibility - just calls the new function
function Clear-RecycleBin {
    <#
    .SYNOPSIS
        Legacy wrapper for Clear-WDCARecycleBin to maintain compatibility
    #>
    return Clear-WDCARecycleBin
}
function Clear-RecycleBin {
    <#
    .SYNOPSIS
        Empties the Recycle Bin

    .DESCRIPTION
        Clears all files from the Recycle Bin to free up space
    #>

    try {
        # Use PowerShell 5.0+ cmdlet if available
        if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Logger "Recycle bin emptied using Clear-RecycleBin" "INFO"
            return "Recycle bin emptied"
        }
        else {
            # Fallback method
            $recycleBin = (New-Object -ComObject Shell.Application).Namespace(0xA)
            $recycleBin.Items() | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
            Write-Logger "Recycle bin emptied using fallback method" "INFO"
            return "Recycle bin emptied"
        }
    }
    catch {
        Write-Logger "Error emptying recycle bin: $($_.Exception.Message)" "WARNING"
        return "Error emptying recycle bin"
    }
}
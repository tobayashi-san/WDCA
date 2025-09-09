function Invoke-DiskCleanup {
    <#
    .SYNOPSIS
        Runs Windows Disk Cleanup utility

    .DESCRIPTION
        Executes cleanmgr.exe to perform additional system cleanup
    #>

    try {
        # Run disk cleanup with preset options
        $cleanmgrArgs = @("/sagerun:0001")

        # Set cleanup options in registry first
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        $cleanupItems = @(
            "Downloaded Program Files",
            "Internet Cache Files",
            "System error memory dump files",
            "System error minidump files",
            "D3D Shader Cache",
            "Delivery Optimization Files",
            "Temporary Files",
            "Thumbnail Cache"
        )

        foreach ($item in $cleanupItems) {
            $itemPath = Join-Path $regPath $item
            if (Test-Path $itemPath) {
                Set-ItemProperty -Path $itemPath -Name "StateFlags0001" -Value 2 -ErrorAction SilentlyContinue
            }
        }

        # Run cleanup
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList $cleanmgrArgs -Wait -NoNewWindow -ErrorAction SilentlyContinue

        Write-Logger "Disk cleanup completed" "INFO"
    }
    catch {
        Write-Logger "Error running disk cleanup: $($_.Exception.Message)" "WARNING"
    }
}
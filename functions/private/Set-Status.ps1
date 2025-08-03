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
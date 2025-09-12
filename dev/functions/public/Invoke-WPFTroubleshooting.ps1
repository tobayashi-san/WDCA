function Invoke-WPFTroubleshooting {
    <#
    .SYNOPSIS
        Handles system diagnostics and troubleshooting

    .DESCRIPTION
        Runs various system diagnostic tools and network tests

    .PARAMETER Action
        The troubleshooting action to perform

    .EXAMPLE
        Invoke-WPFTroubleshooting -Action "SystemDiagnostics"
        Invoke-WPFTroubleshooting -Action "NetworkDiagnostics"
    #>

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("SystemDiagnostics", "NetworkDiagnostics", "DISM", "SFC", "CHKDSK")]
        [string]$Action
    )

    Write-Logger "Starting troubleshooting action: $Action" "INFO"

    switch ($Action) {
        "SystemDiagnostics" {
            Invoke-SystemDiagnosticsAsync
        }
        "DISM" {
            Invoke-DISMScan
        }
        "SFC" {
            Invoke-SFCScan
        }
        "CHKDSK" {
            Invoke-CHKDSKScan
        }
    }
}
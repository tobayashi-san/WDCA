function Invoke-WPFSystemSetup {
    <#
    .SYNOPSIS
        Handles system configuration tasks

    .DESCRIPTION
        Configures network settings, enables RDP, and applies server roles

    .PARAMETER Action
        The configuration action to perform (Network, RDP, Role)

    .EXAMPLE
        Invoke-WPFSystemSetup -Action "Network"
        Invoke-WPFSystemSetup -Action "RDP"
        Invoke-WPFSystemSetup -Action "Role"
    #>

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Network", "RDP", "Role")]
        [string]$Action
    )

    Write-Logger "Starting system setup action: $Action" "INFO"

    switch ($Action) {
        "Network" {
            Invoke-NetworkConfiguration
        }
        "RDP" {
            Invoke-RDPConfiguration
        }
    }
}
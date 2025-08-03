function Invoke-WPFCloning {
    <#
    .SYNOPSIS
        Handles system cloning and imaging preparation

    .DESCRIPTION
        Prepares systems for cloning using Sysprep and cleanup operations

    .PARAMETER Action
        The cloning action to perform

    .EXAMPLE
        Invoke-WPFCloning -Action "Sysprep"
        Invoke-WPFCloning -Action "Cleanup"
    #>

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Sysprep", "Cleanup", "Prepare")]
        [string]$Action
    )

    Write-Logger "Starting cloning action: $Action" "INFO"

    switch ($Action) {
        "Sysprep" {
            Invoke-SystemSysprep
        }
        "Cleanup" {
            Invoke-PreCloneCleanup
        }
        "Prepare" {
            Invoke-SysprepPreparation
        }
    }
}
function Test-IsAdmin {
    <#
    .SYNOPSIS
        Tests if the current user has administrator privileges

    .DESCRIPTION
        Checks if the current PowerShell session is running with administrator rights

    .EXAMPLE
        Test-IsAdmin
    #>

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
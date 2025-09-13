function Get-SystemThemePreference {
    <#
    .SYNOPSIS
        Detects the system's current theme preference
    #>

    try {
        $appsUseLightTheme = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue

        if ($appsUseLightTheme -and $appsUseLightTheme.AppsUseLightTheme -eq 1) {
            return "Light"
        } else {
            return "Dark"
        }
    }
    catch {
        Write-Logger "Could not detect system theme preference, defaulting to Dark" "WARNING"
        return "Dark"
    }
}
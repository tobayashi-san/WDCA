function Set-WDCATheme {
    <#
    .SYNOPSIS
        Applies a theme to the WDCA application

    .PARAMETER ThemeName
        Name of the theme to apply (Dark, Light)
    #>

    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Dark", "Light")]
        [string]$ThemeName
    )

    if (-not $global:WDCAThemes) {
        Initialize-ThemeManager
    }

    $theme = $global:WDCAThemes[$ThemeName]

    if (-not $theme) {
        Write-Logger "Theme '$ThemeName' not found" "ERROR"
        return
    }

    try {
        Write-Logger "Applying theme: $ThemeName" "INFO"

        # Update resource dictionary with new theme colors
        if ($global:sync.Form -and $global:sync.Form.Resources) {
            $resources = $global:sync.Form.Resources

            # Update color resources
            foreach ($colorName in $theme.Keys) {
                # Skip non-color properties
                if ($colorName -like "*Opacity" -or $colorName -like "*Radius" -or $colorName -like "*Thickness") {
                    continue
                }

                $resourceKey = "${colorName}Brush"
                $colorValue = $theme[$colorName]

                try {
                    $brush = New-Object System.Windows.Media.SolidColorBrush
                    $brush.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($colorValue)

                    if ($resources.Contains($resourceKey)) {
                        $resources[$resourceKey] = $brush
                    } else {
                        $resources.Add($resourceKey, $brush)
                    }
                }
                catch {
                    Write-Logger "Error setting color resource $resourceKey`: $($_.Exception.Message)" "DEBUG"
                }
            }

            Write-Logger "Theme '$ThemeName' applied successfully" "INFO"
        }
    }
    catch {
        Write-Logger "Error applying theme '$ThemeName': $($_.Exception.Message)" "ERROR"
    }
}
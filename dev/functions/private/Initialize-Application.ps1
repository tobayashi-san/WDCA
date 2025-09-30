function Initialize-WDCAApplications {
    <#
    .SYNOPSIS
        Initializes the applications panel with modern UI
    #>

    try {
        if (-not $global:sync.configs.applications) {
            Write-Logger "No applications configuration found" "WARNING"
            return
        }

        if (-not $global:sync.WPFApplicationsPanel) {
            Write-Logger "Applications panel not found in UI" "WARNING"
            return
        }

        Write-Logger "Populating applications panel..." "INFO"

        $appsPanel = $global:sync.WPFApplicationsPanel
        $appsCreated = 0

        # Clear existing content
        $appsPanel.Children.Clear() | Out-Null

        # Group applications by category
        $categories = $global:sync.configs.applications.PSObject.Properties |
            Group-Object { $_.Value.category } |
            Sort-Object Name

        foreach ($category in $categories) {
            # Create category card
            $categoryCard = New-Object System.Windows.Controls.Border
            if ($global:sync.Form.Resources["ModernCard"]) {
                $categoryCard.Style = $global:sync.Form.Resources["ModernCard"]
            } else {
                # Fallback styling
                $categoryCard.Background = [System.Windows.Media.Brushes]::DarkGray
                $categoryCard.CornerRadius = "8"
                $categoryCard.Padding = "16"
                $categoryCard.Margin = "0,0,0,16"
            }

            $categoryStack = New-Object System.Windows.Controls.StackPanel

            # Category header
            $categoryLabel = New-Object System.Windows.Controls.TextBlock
            $categoryLabel.Text = $category.Name
            $categoryLabel.FontWeight = "Bold"
            $categoryLabel.FontSize = 16
            $categoryLabel.Margin = "0,0,0,12"
            $categoryLabel.Foreground = [System.Windows.Media.Brushes]::White
            $categoryStack.Children.Add($categoryLabel) | Out-Null

            # Add applications in this category
            foreach ($app in ($category.Group | Sort-Object { $_.Value.content })) {
                # Create checkbox
                $checkbox = New-Object System.Windows.Controls.CheckBox
                $checkboxName = $app.Name  # Already has WPFInstall prefix
                $checkbox.Name = $checkboxName
                $checkbox.Content = $app.Value.content
                $checkbox.ToolTip = $app.Value.description
                $checkbox.Margin = "0,0,0,8"
                $checkbox.Foreground = [System.Windows.Media.Brushes]::White
                $checkbox.FontSize = 12

                # Apply modern style if available
                if ($global:sync.Form.Resources["FluentCheckBox"]) {
                    $checkbox.Style = $global:sync.Form.Resources["FluentCheckBox"]
                }

                $categoryStack.Children.Add($checkbox) | Out-Null

                # Store reference in sync hashtable
                $global:sync[$checkboxName] = $checkbox
                $appsCreated++
            }

            $categoryCard.Child = $categoryStack
            $appsPanel.Children.Add($categoryCard) | Out-Null
        }
    }
    catch {
        Write-Logger "Error initializing applications: $($_.Exception.Message)" "ERROR"
        Write-Host "Detailed error: $($_.Exception)" -ForegroundColor Red
    }
}

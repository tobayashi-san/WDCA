function Initialize-DebloatApplications {
    try {
        Write-Logger "Initializing debloat applications panel..." "INFO"

        if (-not $global:sync.WPFDebloatPanel) {
            Write-Logger "Debloat panel not found in UI" "ERROR"
            return
        }

        $global:sync.WPFDebloatPanel.Children.Clear()

        # Show loading indicator
        $loadingBorder = New-Object System.Windows.Controls.Border
        $loadingBorder.Style = $global:sync.Form.Resources["ModernCard"]

        $loadingStack = New-Object System.Windows.Controls.StackPanel
        $loadingText = New-Object System.Windows.Controls.TextBlock
        $loadingText.Text = "Scanning installed applications..."
        $loadingText.FontSize = 14
        $loadingText.Foreground = [System.Windows.Media.Brushes]::White
        $loadingText.HorizontalAlignment = "Center"

        $loadingStack.Children.Add($loadingText)
        $loadingBorder.Child = $loadingStack
        $global:sync.WPFDebloatPanel.Children.Add($loadingBorder)

        # Get applications - UWP and Win32 only
        Write-Logger "Scanning installed applications..." "INFO"
        $applications = @()

        # Get UWP/Store Apps
        try {
            Write-Logger "Scanning UWP applications..." "INFO"
            $uwpApps = Get-AppxPackage -AllUsers | Where-Object {
                $_.Name -notlike "Microsoft.Windows*" -and
                $_.Name -notlike "Microsoft.VCRedist*" -and
                $_.Name -notlike "*Framework*" -and
                $_.Name -notlike "*VCLibs*" -and
                $_.PublisherId -ne "cw5n1h2txyewy" -and
                $_.PackageFullName -and
                $_.Name
            }

            foreach ($app in $uwpApps) {
                $displayName = $app.Name
                $version = $app.Version.ToString()
                $publisher = $app.Publisher
                if (-not $publisher) { $publisher = "Unknown" }

                $appObject = [PSCustomObject]@{
                    Name = $app.Name
                    DisplayName = $displayName
                    Version = $version
                    Publisher = $publisher
                    Type = "UWP"
                    PackageFullName = $app.PackageFullName
                    Size = 0
                }
                $applications += $appObject
            }
            Write-Logger "Found $($uwpApps.Count) UWP applications" "INFO"
        }
        catch {
            Write-Logger "Error scanning UWP apps: $($_.Exception.Message)" "WARNING"
        }

        # Get Win32 Programs from Registry - Extended search
        try {
            Write-Logger "Scanning Win32 applications..." "INFO"
            $registryPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            $win32Apps = @()
            foreach ($path in $registryPaths) {
                $pathApps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.DisplayName -and
                        $_.UninstallString -and
                        $_.SystemComponent -ne 1 -and
                        $_.DisplayName -notlike "Microsoft Visual C++*" -and
                        $_.DisplayName -notlike "Microsoft .NET*" -and
                        $_.DisplayName -notlike "*Update*" -and
                        $_.DisplayName -notlike "*Hotfix*"
                    }
                $win32Apps += $pathApps
            }

            # Deduplicate Win32 apps by DisplayName
            $processedNames = @{}
            foreach ($app in $win32Apps) {
                if ($processedNames.ContainsKey($app.DisplayName)) {
                    continue
                }
                $processedNames[$app.DisplayName] = $true

                $size = 0
                if ($app.EstimatedSize) {
                    $size = [math]::Round($app.EstimatedSize / 1024, 2)
                }

                $version = "Unknown"
                if ($app.DisplayVersion) {
                    $version = $app.DisplayVersion
                }

                $publisher = "Unknown"
                if ($app.Publisher) {
                    $publisher = $app.Publisher
                }

                $appObject = [PSCustomObject]@{
                    Name = $app.DisplayName
                    DisplayName = $app.DisplayName
                    Version = $version
                    Publisher = $publisher
                    Type = "Win32"
                    PackageFullName = $app.UninstallString
                    Size = $size
                }
                $applications += $appObject
            }
            Write-Logger "Found $($processedNames.Count) unique Win32 applications" "INFO"
        }
        catch {
            Write-Logger "Error scanning Win32 apps: $($_.Exception.Message)" "WARNING"
        }

        Write-Logger "Total applications found: $($applications.Count)" "INFO"
        $sortedApplications = $applications | Sort-Object DisplayName

        Update-DebloatUI -Applications $sortedApplications

    } catch {
        Write-Logger "Error initializing debloat applications: $($_.Exception.Message)" "ERROR"

        # Show error in UI
        $global:sync.WPFDebloatPanel.Children.Clear()
        $errorBorder = New-Object System.Windows.Controls.Border
        $errorBorder.Style = $global:sync.Form.Resources["ModernCard"]

        $errorStack = New-Object System.Windows.Controls.StackPanel
        $errorText = New-Object System.Windows.Controls.TextBlock
        $errorText.Text = "Error loading applications: $($_.Exception.Message)"
        $errorText.FontSize = 12
        $errorText.Foreground = [System.Windows.Media.Brushes]::Red
        $errorText.TextWrapping = "Wrap"

        $errorStack.Children.Add($errorText)
        $errorBorder.Child = $errorStack
        $global:sync.WPFDebloatPanel.Children.Add($errorBorder)
    }
}

function Invoke-DebloatUninstall {
    Write-Logger "Starting application uninstallation..." "INFO"

    # Collect selected applications
    $selectedApps = @()
    $global:sync.WPFDebloatPanel.Children | ForEach-Object {
        if ($_.Child -is [System.Windows.Controls.StackPanel]) {
            $_.Child.Children | ForEach-Object {
                if ($_ -is [System.Windows.Controls.ScrollViewer]) {
                    $_.Content.Children | ForEach-Object {
                        if ($_ -is [System.Windows.Controls.Grid]) {
                            $checkbox = $_.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] }
                            if ($checkbox -and $checkbox.IsChecked -and $checkbox.Tag) {
                                $selectedApps += $checkbox.Tag
                            }
                        }
                    }
                }
            }
        }
    }

    if ($selectedApps.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No applications selected for uninstallation.", "WDCA", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }

    # Single confirmation for all apps
    $appList = ($selectedApps | ForEach-Object { "• $($_.DisplayName)" }) -join "`n"
    $result = [System.Windows.MessageBox]::Show(
        "Uninstall these $($selectedApps.Count) applications?`n`n$appList`n`nThis will proceed automatically without further prompts.",
        "WDCA - Confirm Uninstallation",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    # Start uninstallation directly in background
    Write-Logger "Starting silent uninstallation of $($selectedApps.Count) applications..." "INFO"

    $successCount = 0
    $errorCount = 0

    foreach ($app in $selectedApps) {
        try {
            Write-Logger "Uninstalling: $($app.DisplayName)" "INFO"

            if ($app.Type -eq "UWP") {
                # UWP app
                Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
                Write-Logger "Successfully removed UWP app: $($app.DisplayName)" "SUCCESS"
                $successCount++
            } else {
                # Win32 app
                $uninstallCmd = $app.PackageFullName

                if ($uninstallCmd -like "*msiexec*") {
                    # MSI Package
                    if ($uninstallCmd -match '{[A-F0-9\-]+}') {
                        $productCode = $matches[0]
                        Write-Logger "Uninstalling MSI package: $productCode" "INFO"
                        Start-Process -FilePath 'msiexec.exe' -ArgumentList '/x', $productCode, '/quiet', '/norestart' -Wait -NoNewWindow
                        Write-Logger "Successfully uninstalled MSI package: $($app.DisplayName)" "SUCCESS"
                        $successCount++
                    } else {
                        throw "Could not extract MSI product code"
                    }
                } else {
                    # Generic uninstaller
                    if ($uninstallCmd -match '^"([^"]+)"(.*)') {
                        $exePath = $matches[1]
                        $arguments = $matches[2].Trim()
                        if ($arguments -and $arguments -notmatch '/S|/silent|/quiet') {
                            $arguments += ' /S'
                        } elseif (-not $arguments) {
                            $arguments = '/S'
                        }
                        if ($arguments) {
                            Start-Process -FilePath $exePath -ArgumentList ($arguments -split ' ' | Where-Object { $_ }) -Wait -NoNewWindow
                        } else {
                            Start-Process -FilePath $exePath -Wait -NoNewWindow
                        }
                    } else {
                        # Direct command
                        if ($uninstallCmd -notmatch '/S|/silent|/quiet') {
                            $uninstallCmd += ' /S'
                        }
                        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $uninstallCmd -Wait -NoNewWindow
                    }
                    Write-Logger "Successfully uninstalled application: $($app.DisplayName)" "SUCCESS"
                    $successCount++
                }
            }
        }
        catch {
            Write-Logger "Failed to uninstall $($app.DisplayName): $($_.Exception.Message)" "ERROR"
            $errorCount++
        }
    }

    # Show final summary
    $summaryMessage = "Uninstallation completed.`n`n"
    $summaryMessage += "Successfully uninstalled: $successCount`n"
    $summaryMessage += "Failed: $errorCount`n"
    $summaryMessage += "Total processed: $($selectedApps.Count)"

    if ($successCount -eq $selectedApps.Count) {
        $icon = [System.Windows.MessageBoxImage]::Information
        $title = "WDCA - Success"
    } elseif ($successCount -gt 0) {
        $icon = [System.Windows.MessageBoxImage]::Warning
        $title = "WDCA - Partial Success"
    } else {
        $icon = [System.Windows.MessageBoxImage]::Error
        $title = "WDCA - Failed"
    }

    [System.Windows.MessageBox]::Show($summaryMessage, $title, [System.Windows.MessageBoxButton]::OK, $icon)

    # Refresh the application list
    Initialize-DebloatApplications
}

function Update-DebloatUI {
    param([array]$Applications)

    try {
        Write-Logger "Updating debloat UI with $($Applications.Count) applications..." "INFO"

        $global:sync.WPFDebloatPanel.Children.Clear()

        if (-not $Applications -or $Applications.Count -eq 0) {
            $noAppsBorder = New-Object System.Windows.Controls.Border
            $noAppsBorder.Style = $global:sync.Form.Resources["ModernCard"]

            $noAppsText = New-Object System.Windows.Controls.TextBlock
            $noAppsText.Text = "No applications found for removal."
            $noAppsText.Foreground = [System.Windows.Media.Brushes]::Gray
            $noAppsText.HorizontalAlignment = "Center"

            $noAppsBorder.Child = $noAppsText
            $global:sync.WPFDebloatPanel.Children.Add($noAppsBorder)
            return
        }

        $mainBorder = New-Object System.Windows.Controls.Border
        $mainBorder.Style = $global:sync.Form.Resources["ModernCard"]

        $mainStack = New-Object System.Windows.Controls.StackPanel

        # Header with statistics
        $headerText = New-Object System.Windows.Controls.TextBlock
        $headerText.Text = "Installed Applications"
        $headerText.FontWeight = "Bold"
        $headerText.FontSize = 16
        $headerText.Foreground = [System.Windows.Media.Brushes]::White
        $mainStack.Children.Add($headerText)

        $uwpCount = ($Applications | Where-Object { $_.Type -eq "UWP" }).Count
        $win32Count = ($Applications | Where-Object { $_.Type -eq "Win32" }).Count

        $statsText = New-Object System.Windows.Controls.TextBlock
        $statsText.Text = "Total: $($Applications.Count) | UWP: $uwpCount | Win32: $win32Count"
        $statsText.FontSize = 11
        $statsText.Foreground = [System.Windows.Media.Brushes]::Gray
        $statsText.Margin = "0,2,0,10"
        $mainStack.Children.Add($statsText)

        # Control buttons
        $buttonStack = New-Object System.Windows.Controls.StackPanel
        $buttonStack.Orientation = "Horizontal"
        $buttonStack.Margin = "0,0,0,10"

        $selectAllBtn = New-Object System.Windows.Controls.Button
        $selectAllBtn.Content = "Select All"
        $selectAllBtn.Style = $global:sync.Form.Resources["FluentButtonSecondary"]
        $selectAllBtn.Margin = "0,0,10,0"

        $deselectAllBtn = New-Object System.Windows.Controls.Button
        $deselectAllBtn.Content = "Deselect All"
        $deselectAllBtn.Style = $global:sync.Form.Resources["FluentButtonSecondary"]

        $buttonStack.Children.Add($selectAllBtn)
        $buttonStack.Children.Add($deselectAllBtn)
        $mainStack.Children.Add($buttonStack)

        # Applications list
        $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
        $scrollViewer.Height = 500
        $scrollViewer.VerticalScrollBarVisibility = "Auto"

        $appsStack = New-Object System.Windows.Controls.StackPanel
        $allCheckboxes = @()

        foreach ($app in $Applications) {
            $appGrid = New-Object System.Windows.Controls.Grid
            $appGrid.Margin = "0,2,0,2"

            # Grid columns
            $col1 = New-Object System.Windows.Controls.ColumnDefinition
            $col1.Width = "Auto"
            $col2 = New-Object System.Windows.Controls.ColumnDefinition
            $col2.Width = "*"
            $col3 = New-Object System.Windows.Controls.ColumnDefinition
            $col3.Width = "Auto"

            $appGrid.ColumnDefinitions.Add($col1)
            $appGrid.ColumnDefinitions.Add($col2)
            $appGrid.ColumnDefinitions.Add($col3)

            # Checkbox
            $checkbox = New-Object System.Windows.Controls.CheckBox
            $checkbox.Style = $global:sync.Form.Resources["FluentCheckBox"]
            $checkbox.Tag = $app
            $checkbox.VerticalAlignment = "Center"
            $checkbox.Margin = "0,0,10,0"
            [System.Windows.Controls.Grid]::SetColumn($checkbox, 0)

            # App info
            $infoStack = New-Object System.Windows.Controls.StackPanel

            $nameText = New-Object System.Windows.Controls.TextBlock
            $nameText.Text = $app.DisplayName
            $nameText.FontWeight = "Medium"
            $nameText.FontSize = 13
            $nameText.Foreground = [System.Windows.Media.Brushes]::White

            $detailText = New-Object System.Windows.Controls.TextBlock
            $detailText.Text = "Version: $($app.Version) | Publisher: $($app.Publisher)"
            if ($app.Size -gt 0) {
                $detailText.Text += " | Size: $($app.Size) MB"
            }
            $detailText.FontSize = 10
            $detailText.Foreground = [System.Windows.Media.Brushes]::Gray

            $infoStack.Children.Add($nameText)
            $infoStack.Children.Add($detailText)
            [System.Windows.Controls.Grid]::SetColumn($infoStack, 1)

            # Type badge
            $typeBadge = New-Object System.Windows.Controls.Border
            $typeBadge.CornerRadius = 3
            $typeBadge.Padding = "6,2"

            if ($app.Type -eq "UWP") {
                $typeBadge.Background = [System.Windows.Media.Brushes]::DarkBlue
            } else {
                $typeBadge.Background = [System.Windows.Media.Brushes]::DarkOrange
            }

            $typeText = New-Object System.Windows.Controls.TextBlock
            $typeText.Text = $app.Type
            $typeText.FontSize = 10
            $typeText.FontWeight = "Bold"
            $typeText.Foreground = [System.Windows.Media.Brushes]::White

            $typeBadge.Child = $typeText
            [System.Windows.Controls.Grid]::SetColumn($typeBadge, 2)

            $appGrid.Children.Add($checkbox)
            $appGrid.Children.Add($infoStack)
            $appGrid.Children.Add($typeBadge)
            $appsStack.Children.Add($appGrid)

            $allCheckboxes += $checkbox
        }

        # Wire up button events
        $selectAllBtn.Add_Click({
            foreach ($cb in $allCheckboxes) {
                $cb.IsChecked = $true
            }
        }.GetNewClosure())

        $deselectAllBtn.Add_Click({
            foreach ($cb in $allCheckboxes) {
                $cb.IsChecked = $false
            }
        }.GetNewClosure())

        $scrollViewer.Content = $appsStack
        $mainStack.Children.Add($scrollViewer)
        $mainBorder.Child = $mainStack
        $global:sync.WPFDebloatPanel.Children.Add($mainBorder)

        Write-Logger "Successfully populated debloat UI with $($Applications.Count) applications" "SUCCESS"

    } catch {
        Write-Logger "Error updating debloat UI: $($_.Exception.Message)" "ERROR"
    }
}
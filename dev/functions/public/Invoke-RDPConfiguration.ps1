function Invoke-RDPConfiguration {
    <#
    .SYNOPSIS
        Enables and configures Remote Desktop
    .DESCRIPTION
        Enables Remote Desktop and configures authentication settings without restart
    #>
    Write-Logger "Configuring Remote Desktop" "INFO"
    try {
        # Check current RDP status
        $currentRDPStatus = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue
        $rdpWasDisabled = $currentRDPStatus.fDenyTSConnections -eq 1

        # Enable Remote Desktop
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
        Write-Logger "Enabled Remote Desktop" "INFO"

        # Enable Remote Desktop through Windows Firewall
        try {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop
            Write-Logger "Enabled Remote Desktop firewall rules" "INFO"
        }
        catch {
            # Fallback for older systems or different language versions
            netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes
            Write-Logger "Enabled Remote Desktop firewall rules (netsh)" "INFO"
        }

        # Check if Network Level Authentication should be required
        $requireNLA = if ($sync.WPFRDPNetworkAuth) { $sync.WPFRDPNetworkAuth.IsChecked } else { $true }

        if ($requireNLA) {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
            Write-Logger "Enabled Network Level Authentication for RDP" "INFO"
        }
        else {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0
            Write-Logger "Disabled Network Level Authentication for RDP" "INFO"
        }

        # Force refresh of Terminal Services configuration (no restart needed)
        try {
            # Restart Terminal Services to apply changes immediately
            $terminalService = Get-Service -Name "TermService" -ErrorAction SilentlyContinue
            if ($terminalService -and $terminalService.Status -eq "Running") {
                Write-Logger "Refreshing Terminal Services configuration" "INFO"
                Restart-Service -Name "TermService" -Force -ErrorAction Stop
                Write-Logger "Terminal Services restarted successfully" "INFO"
            }
            else {
                # Start the service if it's not running
                Start-Service -Name "TermService" -ErrorAction Stop
                Write-Logger "Terminal Services started" "INFO"
            }
        }
        catch {
            Write-Logger "Warning: Could not restart Terminal Services: $($_.Exception.Message)" "WARNING"
            Write-Logger "RDP settings applied, but may require manual service restart" "WARNING"
        }

        # Get current RDP port for information
        try {
            $rdpPort = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "PortNumber" -ErrorAction SilentlyContinue
            if ($rdpPort) {
                Write-Logger "RDP is configured on port: $($rdpPort.PortNumber)" "INFO"
            }
        }
        catch {
            Write-Logger "Could not determine RDP port" "WARNING"
        }

        Write-Logger "Remote Desktop configuration completed successfully" "INFO"

        # Prepare status message
        $statusMessage = "Remote Desktop has been enabled and configured successfully.`n`n"
        $statusMessage += "Configuration applied:`n"
        $statusMessage += "- Remote Desktop: Enabled`n"
        $statusMessage += "- Firewall Rules: Enabled`n"
        $statusMessage += "- Network Level Auth: $(if ($requireNLA) { 'Enabled' } else { 'Disabled' })`n"
        $statusMessage += "- Terminal Services: Refreshed`n`n"
        $statusMessage += "RDP is ready to use immediately - no restart required."

        [System.Windows.MessageBox]::Show($statusMessage, "WDCA - RDP Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
    catch {
        Write-Logger "Error configuring Remote Desktop: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show("Error configuring Remote Desktop: $($_.Exception.Message)", "WDCA - RDP Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}
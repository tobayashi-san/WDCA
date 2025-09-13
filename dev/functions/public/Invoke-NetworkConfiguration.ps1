function Invoke-NetworkConfiguration {
    <#
    .SYNOPSIS
        Configures network settings
    .DESCRIPTION
        Sets IP address, subnet mask, gateway, DNS servers, IPv6 settings, or enables DHCP
    #>
    Write-Logger "Configuring network settings" "INFO"

    # Get values from UI
    $useDHCP = if ($sync.WPFDHCP) { $sync.WPFDHCP.IsChecked } else { $false }
    $useStaticIP = if ($sync.WPFStaticIP) { $sync.WPFStaticIP.IsChecked } else { $true }
    $ipAddress = if ($sync.WPFNetworkIP) { $sync.WPFNetworkIP.Text.Trim() } else { "" }
    $subnetMask = if ($sync.WPFNetworkSubnet) { $sync.WPFNetworkSubnet.Text.Trim() } else { "" }
    $gateway = if ($sync.WPFNetworkGateway) { $sync.WPFNetworkGateway.Text.Trim() } else { "" }
    $dnsServer = if ($sync.WPFNetworkDNS) { $sync.WPFNetworkDNS.Text.Trim() } else { "" }
    $dnsAltServer = if ($sync.WPFNetworkDNSAlt) { $sync.WPFNetworkDNSAlt.Text.Trim() } else { "" }
    $disableIPv6 = if ($sync.WPFDisableIPv6) { $sync.WPFDisableIPv6.IsChecked } else { $false }

    # Validate input for Static IP
    if ($useStaticIP -and [string]::IsNullOrEmpty($ipAddress)) {
        Write-Logger "IP Address is required for static IP configuration" "ERROR"
        [System.Windows.MessageBox]::Show("Please enter an IP address for static configuration.", "WDCA - Network Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    # Validate IP address format for Static IP
    if ($useStaticIP) {
        try {
            [System.Net.IPAddress]::Parse($ipAddress) | Out-Null
        }
        catch {
            Write-Logger "Invalid IP address format: $ipAddress" "ERROR"
            [System.Windows.MessageBox]::Show("Please enter a valid IP address.", "WDCA - Network Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }
    }

    try {
        # Get the primary network adapter
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceType -eq 6 } | Select-Object -First 1
        if (-not $adapter) {
            Write-Logger "No active network adapter found" "ERROR"
            [System.Windows.MessageBox]::Show("No active network adapter found.", "WDCA - Network Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }

        Write-Logger "Configuring adapter: $($adapter.Name)" "INFO"

        if ($useDHCP) {
            # Configure DHCP
            Write-Logger "Enabling DHCP configuration" "INFO"

            # Remove existing static IP configuration
            Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

            # Enable DHCP for IP address
            Set-NetIPInterface -InterfaceAlias $adapter.Name -Dhcp Enabled -ErrorAction Stop
            Write-Logger "DHCP enabled for IP address" "INFO"

            # Set DNS to automatic (DHCP) - always use automatic DNS with DHCP
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses -ErrorAction Stop
            Write-Logger "DNS set to automatic (DHCP)" "INFO"

            # Renew DHCP lease to get new configuration
            $null = Invoke-Command -ScriptBlock { ipconfig /renew } -ErrorAction SilentlyContinue
            Write-Logger "DHCP lease renewed" "INFO"
        }
        else {
            # Configure Static IP
            Write-Logger "Configuring static IP" "INFO"

            # Remove existing IP configuration
            Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

            # Disable DHCP
            Set-NetIPInterface -InterfaceAlias $adapter.Name -Dhcp Disabled -ErrorAction Stop

            # Convert subnet mask to prefix length if provided
            $prefixLength = 24  # Default /24
            if (-not [string]::IsNullOrEmpty($subnetMask)) {
                $prefixLength = Convert-SubnetMaskToPrefixLength $subnetMask
            }

            # Set IP address
            New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $ipAddress -PrefixLength $prefixLength -ErrorAction Stop
            Write-Logger "Set static IP address: $ipAddress/$prefixLength" "INFO"

            # Set gateway if provided
            if (-not [string]::IsNullOrEmpty($gateway)) {
                New-NetRoute -InterfaceAlias $adapter.Name -DestinationPrefix "0.0.0.0/0" -NextHop $gateway -ErrorAction Stop
                Write-Logger "Set gateway: $gateway" "INFO"
            }

            # Set DNS servers if provided
            $dnsServers = @()
            if (-not [string]::IsNullOrEmpty($dnsServer)) {
                $dnsServers += $dnsServer
            }
            if (-not [string]::IsNullOrEmpty($dnsAltServer)) {
                $dnsServers += $dnsAltServer
            }

            if ($dnsServers.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsServers -ErrorAction Stop
                Write-Logger "Set DNS servers: $($dnsServers -join ', ')" "INFO"
            }
        }

        # Handle IPv6 settings (applies to both DHCP and Static)
        if ($disableIPv6) {
            # Disable IPv6 on the adapter
            Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            Write-Logger "IPv6 disabled on adapter: $($adapter.Name)" "INFO"

            # Also disable IPv6 globally via registry (requires reboot to take full effect)
            try {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 0xff -Type DWord -ErrorAction Stop
                Write-Logger "IPv6 disabled globally (registry)" "INFO"
            }
            catch {
                Write-Logger "Warning: Could not disable IPv6 globally via registry: $($_.Exception.Message)" "WARNING"
            }
        }
        else {
            # Enable IPv6 on the adapter if it was disabled
            Enable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            Write-Logger "IPv6 enabled on adapter: $($adapter.Name)" "INFO"

            # Enable IPv6 globally via registry
            try {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 0x00 -Type DWord -ErrorAction Stop
                Write-Logger "IPv6 enabled globally (registry)" "INFO"
            }
            catch {
                Write-Logger "Warning: Could not enable IPv6 globally via registry: $($_.Exception.Message)" "WARNING"
            }
        }

        Write-Logger "Network configuration completed successfully" "INFO"

        # Show completion message
        $configType = if ($useDHCP) { "DHCP" } else { "Static IP" }
        $ipv6Status = if ($disableIPv6) { "IPv6 wurde deaktiviert." } else { "IPv6 ist aktiviert." }
        $message = "Network configuration completed successfully.`n`nConfiguration: $configType`n$ipv6Status"

        if ($disableIPv6) {
            $message += "`n`nHinweis: Ein Neustart wird empfohlen für vollständige IPv6-Deaktivierung."
        }

        if ($useDHCP) {
            $message += "`n`nDHCP lease wurde erneuert. Neue IP-Konfiguration wird automatisch bezogen."
        }

        [System.Windows.MessageBox]::Show($message, "WDCA - Network Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
    catch {
        Write-Logger "Error configuring network: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show("Error configuring network: $($_.Exception.Message)", "WDCA - Network Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}
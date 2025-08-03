function Invoke-DomainControllerUpgradePrep {
    <#
    .SYNOPSIS
        Prepares Active Directory Domain Controller for Windows In-Place Upgrade

    .DESCRIPTION
        Comprehensive preparation for DC in-place upgrade including Forest Prep, Domain Prep,
        FSMO role analysis, replication health, and AD-specific readiness checks.

    .PARAMETER TargetWindowsVersion
        Target Windows Server version for upgrade

    .PARAMETER PerformForestPrep
        Whether to perform Forest Prep operations

    .PARAMETER PerformDomainPrep
        Whether to perform Domain Prep operations

    .EXAMPLE
        Invoke-DomainControllerUpgradePrep -TargetWindowsVersion "2022"
        Invoke-DomainControllerUpgradePrep -PerformForestPrep -PerformDomainPrep
    #>

    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("2019", "2022", "2025")]
        [string]$TargetWindowsVersion = "2022",

        [Parameter(Mandatory = $false)]
        [switch]$PerformForestPrep,

        [Parameter(Mandatory = $false)]
        [switch]$PerformDomainPrep
    )

    Write-Logger "Starting Domain Controller Upgrade Preparation for Windows Server $TargetWindowsVersion" "INFO"

    try {
        # Confirmation dialog with DC-specific warnings
        $confirmMessage = @"
Prepare Domain Controller for Windows Server $TargetWindowsVersion In-Place Upgrade?

  CRITICAL WARNINGS:
- Domain Controller upgrade affects entire AD environment
- Forest/Domain Prep may be required
- FSMO role holders need special consideration
- Replication must be healthy before upgrade
- Extended downtime expected

Continue with DC upgrade preparation?
"@

        $confirmResult = [System.Windows.MessageBox]::Show(
            $confirmMessage,
            "WDCA - Domain Controller Upgrade Preparation",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )

        if ($confirmResult -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-Logger "DC upgrade preparation cancelled by user" "INFO"
            return
        }

        # Main DC upgrade preparation script
        $dcUpgradeScript = {
            param($targetVersion, $forestPrep, $domainPrep)

            $results = @()
            $warnings = @()
            $errors = @()
            $recommendations = @()
            $forestPrepRequired = $false
            $domainPrepRequired = $false

            try {
                $results += "=== DOMAIN CONTROLLER UPGRADE PREPARATION ==="
                $results += "Target Windows Version: Server $targetVersion"
                $results += "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $results += ""

                # Import AD Module
                $results += "=== Active Directory Module Check ==="
                try {
                    Import-Module ActiveDirectory -ErrorAction Stop
                    $results += "AD PowerShell Module: LOADED"
                } catch {
                    $errors += "Active Directory PowerShell module not available"
                    $results += "AD PowerShell Module: FAILED TO LOAD"
                    $results += "Install RSAT-AD-PowerShell feature or AD management tools"
                    throw "Cannot proceed without AD PowerShell module"
                }
                $results += ""

                # Current DC Information
                $results += "=== DOMAIN CONTROLLER ANALYSIS ==="
                $computer = Get-ADComputer -Identity $env:COMPUTERNAME -Properties OperatingSystem, OperatingSystemVersion
                $domain = Get-ADDomain
                $forest = Get-ADForest

                $results += "Current DC: $($computer.Name)"
                $results += "Current OS: $($computer.OperatingSystem) $($computer.OperatingSystemVersion)"
                $results += "Domain: $($domain.DNSRoot)"
                $results += "Forest: $($forest.Name)"
                $results += "Domain Functional Level: $($domain.DomainMode)"
                $results += "Forest Functional Level: $($forest.ForestMode)"
                $results += ""

                # FSMO Roles Analysis
                $results += "=== FSMO ROLES ANALYSIS ==="
                $forestFSMO = @{
                    'Schema Master' = $forest.SchemaMaster
                    'Domain Naming Master' = $forest.DomainNamingMaster
                }

                $domainFSMO = @{
                    'PDC Emulator' = $domain.PDCEmulator
                    'RID Master' = $domain.RIDMaster
                    'Infrastructure Master' = $domain.InfrastructureMaster
                }

                $currentDC = "$($env:COMPUTERNAME).$($domain.DNSRoot)"
                $fsmoRoles = @()

                foreach ($role in $forestFSMO.GetEnumerator()) {
                    $results += "$($role.Key): $($role.Value)"
                    if ($role.Value -eq $currentDC) {
                        $fsmoRoles += $role.Key
                        $warnings += "This DC holds Forest-wide FSMO role: $($role.Key)"
                    }
                }

                foreach ($role in $domainFSMO.GetEnumerator()) {
                    $results += "$($role.Key): $($role.Value)"
                    if ($role.Value -eq $currentDC) {
                        $fsmoRoles += $role.Key
                        $warnings += "This DC holds Domain FSMO role: $($role.Key)"
                    }
                }

                if ($fsmoRoles.Count -gt 0) {
                    $results += ""
                    $results += "THIS DC HOLDS $($fsmoRoles.Count) FSMO ROLE(S):"
                    foreach ($role in $fsmoRoles) {
                        $results += "   - $role"
                    }
                    $recommendations += "Consider transferring FSMO roles to another DC before upgrade"
                    $recommendations += "Document FSMO role transfer procedures"
                } else {
                    $results += "This DC holds no FSMO roles - safer for upgrade"
                }
                $results += ""

                # Forest/Domain Functional Level Check
                $results += "=== FUNCTIONAL LEVEL COMPATIBILITY ==="

                # Windows Server version to functional level mapping
                $versionMapping = @{
                    "2019" = @{ Forest = "Windows2016Forest"; Domain = "Windows2016Domain"; MinFL = "2016" }
                    "2022" = @{ Forest = "Windows2016Forest"; Domain = "Windows2016Domain"; MinFL = "2016" }
                    "2025" = @{ Forest = "Windows2016Forest"; Domain = "Windows2016Domain"; MinFL = "2016" }
                }

                $targetMapping = $versionMapping[$targetVersion]
                $currentForestFL = $forest.ForestMode.ToString()
                $currentDomainFL = $domain.DomainMode.ToString()

                $results += "Current Forest FL: $currentForestFL"
                $results += "Current Domain FL: $currentDomainFL"
                $results += "Required for Server $targetVersion`: $($targetMapping.MinFL) or higher"

                # Check if Forest Prep is needed
                if ($currentForestFL -lt $targetMapping.Forest) {
                    $forestPrepRequired = $true
                    $warnings += "Forest Prep required: Current FL ($currentForestFL) < Required FL"
                    $recommendations += "Run adprep /forestprep before any DC upgrade in forest"
                } else {
                    $results += "Forest functional level compatible"
                }

                # Check if Domain Prep is needed
                if ($currentDomainFL -lt $targetMapping.Domain) {
                    $domainPrepRequired = $true
                    $warnings += "Domain Prep required: Current FL ($currentDomainFL) < Required FL"
                    $recommendations += "Run adprep /domainprep in each domain"
                } else {
                    $results += "Domain functional level compatible"
                }
                $results += ""

                # AD Replication Health
                $results += "=== REPLICATION HEALTH CHECK ==="
                try {
                    # Check replication partners
                    $replPartners = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction Stop
                    $results += "Replication Partners: $($replPartners.Count)"

                    $replErrors = 0
                    foreach ($partner in $replPartners) {
                        if ($partner.LastReplicationResult -ne 0) {
                            $replErrors++
                            $errors += "Replication error with $($partner.Partner): Error $($partner.LastReplicationResult)"
                        }
                    }

                    if ($replErrors -eq 0) {
                        $results += "All replication partners healthy"
                    } else {
                        $results += "$replErrors replication errors found"
                        $recommendations += "Fix all replication errors before upgrade"
                    }

                    # Check replication failures
                    $replFailures = Get-ADReplicationFailure -Target $env:COMPUTERNAME -ErrorAction SilentlyContinue
                    if ($replFailures) {
                        $results += "Replication Failures: $($replFailures.Count)"
                        $errors += "Active replication failures detected"
                        $recommendations += "Resolve replication failures: repadmin /showrepl"
                    } else {
                        $results += "No replication failures"
                    }

                } catch {
                    $warnings += "Could not check replication health: $($_.Exception.Message)"
                    $recommendations += "Manually verify replication: repadmin /replsummary"
                }
                $results += ""

                # SYSVOL Health
                $results += "=== SYSVOL HEALTH CHECK ==="
                try {
                    $sysvol = "$env:SystemRoot\SYSVOL"
                    if (Test-Path $sysvol) {
                        $sysvolSize = (Get-ChildItem $sysvol -Recurse -File | Measure-Object -Property Length -Sum).Sum
                        $sysvolSizeGB = [math]::Round($sysvolSize / 1GB, 2)
                        $results += "SYSVOL Path: $sysvol"
                        $results += "SYSVOL Size: $sysvolSizeGB GB"

                        # Check DFSR vs FRS
                        $dfsrService = Get-Service -Name DFSR -ErrorAction SilentlyContinue
                        $ntfrsService = Get-Service -Name NtFrs -ErrorAction SilentlyContinue

                        if ($dfsrService -and $dfsrService.Status -eq "Running") {
                            $results += "SYSVOL Replication: DFSR (recommended)"
                        } elseif ($ntfrsService -and $ntfrsService.Status -eq "Running") {
                            $warnings += "SYSVOL using legacy FRS replication"
                            $recommendations += "Consider migrating to DFSR before upgrade"
                            $results += "SYSVOL Replication: FRS (legacy)"
                        }
                    } else {
                        $errors += "SYSVOL path not found: $sysvol"
                    }
                } catch {
                    $warnings += "Could not check SYSVOL health: $($_.Exception.Message)"
                }
                $results += ""

                # Directory Services Storage
                $results += "=== ACTIVE DIRECTORY DATABASE ==="
                try {
                    # Get NTDS database path
                    $ntdsPath = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "DSA Database file").('DSA Database file')
                    $logPath = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "Database log files path").('Database log files path')

                    $results += "NTDS Database: $ntdsPath"
                    $results += "NTDS Logs: $logPath"

                    if (Test-Path $ntdsPath) {
                        $dbSize = (Get-Item $ntdsPath).Length
                        $dbSizeGB = [math]::Round($dbSize / 1GB, 2)
                        $results += "Database Size: $dbSizeGB GB"

                        # Check available space on DB drive
                        $dbDrive = (Split-Path $ntdsPath -Qualifier)
                        $driveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $dbDrive }
                        $freeSpaceGB = [math]::Round($driveInfo.FreeSpace / 1GB, 2)

                        $results += "Available Space on $dbDrive`: $freeSpaceGB GB"

                        if ($freeSpaceGB -lt ($dbSizeGB * 2)) {
                            $warnings += "Low disk space for AD database operations"
                            $recommendations += "Ensure at least double DB size free space for upgrade"
                        }
                    }
                } catch {
                    $warnings += "Could not analyze AD database: $($_.Exception.Message)"
                }
                $results += ""

                # DNS Configuration
                $results += "=== DNS CONFIGURATION ==="
                try {
                    $dnsService = Get-Service -Name DNS -ErrorAction SilentlyContinue
                    if ($dnsService) {
                        $results += "DNS Service: $($dnsService.Status)"

                        # Check if this DC is also a DNS server
                        if ($dnsService.Status -eq "Running") {
                            $results += "This DC is also a DNS server"

                            # Check DNS zones
                            $dnsZones = Get-DnsServerZone -ErrorAction SilentlyContinue
                            if ($dnsZones) {
                                $adIntegratedZones = $dnsZones | Where-Object { $_.ZoneType -eq "Primary" -and $_.IsDsIntegrated }
                                $results += "AD-Integrated DNS Zones: $($adIntegratedZones.Count)"
                                $recommendations += "Verify DNS zone replication after upgrade"
                            }
                        }
                    } else {
                        $results += "DNS Service: Not installed on this DC"
                        $warnings += "External DNS server must support SRV records for AD"
                    }
                } catch {
                    $warnings += "Could not check DNS configuration: $($_.Exception.Message)"
                }
                $results += ""

                # Global Catalog Status
                $results += "=== GLOBAL CATALOG STATUS ==="
                try {
                    $gcStatus = Get-ADDomainController -Identity $env:COMPUTERNAME | Select-Object IsGlobalCatalog
                    if ($gcStatus.IsGlobalCatalog) {
                        $results += "This DC is a Global Catalog server"
                        $warnings += "GC server upgrade may affect cross-domain authentication"
                        $recommendations += "Ensure other GC servers are available during upgrade"
                    } else {
                        $results += "This DC is not a Global Catalog server"
                    }
                } catch {
                    $warnings += "Could not check Global Catalog status: $($_.Exception.Message)"
                }
                $results += ""

                # ADPREP Requirements
                $results += "=== ADPREP PREPARATION REQUIREMENTS ==="

                if ($forestPrepRequired -or $forestPrep) {
                    $results += "FOREST PREP REQUIRED:"
                    $results += "1. Must be run on Schema Master: $($forest.SchemaMaster)"
                    $results += "2. User must be member of Schema Admins and Enterprise Admins"
                    $results += "3. Command: adprep /forestprep"
                    $results += "4. Location: Server $targetVersion installation media \\support\\adprep\\"
                    $recommendations += "Run Forest Prep on Schema Master before any DC upgrade"
                    $recommendations += "Verify Schema Admins and Enterprise Admins group membership"
                }

                if ($domainPrepRequired -or $domainPrep) {
                    $results += "DOMAIN PREP REQUIRED:"
                    $results += "1. Must be run on Infrastructure Master: $($domain.InfrastructureMaster)"
                    $results += "2. User must be member of Domain Admins"
                    $results += "3. Command: adprep /domainprep"
                    $results += "4. Run in each domain that will have Server $targetVersion DCs"
                    $recommendations += "Run Domain Prep on Infrastructure Master in each domain"
                }

                if (!$forestPrepRequired -and !$domainPrepRequired) {
                    $results += "No ADPREP operations required"
                }
                $results += ""

                # Backup Recommendations
                $results += "=== BACKUP REQUIREMENTS ==="
                $results += "CRITICAL: Perform these backups before upgrade:"
                $results += "1. System State Backup (includes AD database)"
                $results += "   Command: wbadmin start systemstatebackup -backuptarget:X:"
                $results += "2. Full Server Backup (recommended)"
                $results += "3. Export DHCP configuration (if DHCP role installed)"
                $results += "4. Document DNS zones and settings"
                $results += "5. Export Group Policy Objects"
                $results += "   Command: Backup-GPO -All -Path C:\\GPOBackup"
                $recommendations += "Test backup restoration procedures before upgrade"
                $recommendations += "Verify backup completeness and accessibility"
                $results += ""

                # Upgrade Order Recommendations
                $results += "=== UPGRADE ORDER STRATEGY ==="
                if ($fsmoRoles.Count -gt 0) {
                    $results += "FSMO ROLE HOLDER DETECTED"
                    $results += "Recommended upgrade order:"
                    $results += "1. Upgrade non-FSMO DCs first"
                    $results += "2. Transfer FSMO roles to upgraded DCs"
                    $results += "3. Upgrade this DC last"
                    $recommendations += "Consider temporarily transferring FSMO roles"
                } else {
                    $results += "Safe to upgrade early (no FSMO roles)"
                    $results += "Recommended: Upgrade after ADPREP but before FSMO holders"
                }
                $results += ""

                # Post-Upgrade Verification
                $results += "=== POST-UPGRADE VERIFICATION CHECKLIST ==="
                $results += "After upgrade, verify:"
                $results += "- Active Directory service starts successfully"
                $results += "- Domain controller advertises all services"
                $results += "   Command: dcdiag /test:advertising"
                $results += "- Replication is working"
                $results += "   Command: repadmin /replsummary"
                $results += "- SYSVOL share is accessible"
                $results += "- DNS service (if installed) is working"
                $results += "- Global Catalog promotion (if applicable)"
                $results += "- Client authentication and logon"
                $results += "- Group Policy application"
                $results += "- Time synchronization with PDC"
                $results += ""

                # Calculate readiness score
                $readinessScore = 100
                if ($errors.Count -gt 0) { $readinessScore -= ($errors.Count * 30) }
                if ($warnings.Count -gt 0) { $readinessScore -= ($warnings.Count * 15) }
                if ($forestPrepRequired) { $readinessScore -= 20 }
                if ($domainPrepRequired) { $readinessScore -= 15 }
                if ($fsmoRoles.Count -gt 0) { $readinessScore -= 10 }

                $readinessLevel = if ($readinessScore -ge 85) { "EXCELLENT" }
                                 elseif ($readinessScore -ge 70) { "GOOD" }
                                 elseif ($readinessScore -ge 50) { "FAIR" }
                                 else { "POOR" }

                # Summary
                $results += "=== DOMAIN CONTROLLER UPGRADE READINESS ==="
                $results += "Readiness Score: $readinessScore/100 ($readinessLevel)"
                $results += "Target Version: Windows Server $targetVersion"
                $results += "FSMO Roles: $($fsmoRoles.Count)"
                $results += "Forest Prep Required: $(if ($forestPrepRequired) { 'YES' } else { 'NO' })"
                $results += "Domain Prep Required: $(if ($domainPrepRequired) { 'YES' } else { 'NO' })"
                $results += "Errors: $($errors.Count)"
                $results += "Warnings: $($warnings.Count)"
                $results += ""

                if ($errors.Count -gt 0) {
                    $results += "=== CRITICAL ISSUES ==="
                    foreach ($error in $errors) {
                        $results += "$error"
                    }
                    $results += ""
                }

                if ($warnings.Count -gt 0) {
                    $results += "=== WARNINGS ==="
                    foreach ($warning in $warnings) {
                        $results += "$warning"
                    }
                    $results += ""
                }

                if ($recommendations.Count -gt 0) {
                    $results += "=== RECOMMENDATIONS ==="
                    foreach ($recommendation in $recommendations) {
                        $results += "- $recommendation"
                    }
                    $results += ""
                }

                # Final recommendation
                $results += "=== FINAL RECOMMENDATION ==="
                if ($errors.Count -eq 0 -and !$forestPrepRequired -and !$domainPrepRequired) {
                    $results += "PROCEED: DC is ready for in-place upgrade"
                    $results += "- Complete System State backup before proceeding"
                    $results += "- Monitor replication during and after upgrade"
                } elseif ($errors.Count -eq 0) {
                    $results += "PROCEED AFTER PREPARATION: Address requirements first"
                    $results += "- Complete Forest/Domain Prep if required"
                    $results += "- Address all warnings where possible"
                    $results += "- Follow recommended upgrade order"
                } else {
                    $results += "DO NOT PROCEED: Critical issues must be resolved"
                    $results += "- Fix all replication errors"
                    $results += "- Resolve storage and configuration issues"
                    $results += "- Re-run preparation after fixes"
                }

                $results += ""
                $results += "DC upgrade preparation completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

            } catch {
                $errors += "Critical error during DC preparation: $($_.Exception.Message)"
                $results += "ERROR: $($_.Exception.Message)"
            }

            return @{
                Results = $results
                TargetVersion = $targetVersion
                Errors = $errors.Count
                Warnings = $warnings.Count
                FSMORoles = $fsmoRoles.Count
                ForestPrepRequired = $forestPrepRequired
                DomainPrepRequired = $domainPrepRequired
                ReadinessScore = if ($readinessScore) { $readinessScore } else { 0 }
                ReadinessLevel = if ($readinessLevel) { $readinessLevel } else { "UNKNOWN" }
            }
        }

        # Start async operation
        Start-AsyncOperation -ScriptBlock {
            & $dcUpgradeScript $TargetWindowsVersion $PerformForestPrep.IsPresent $PerformDomainPrep.IsPresent
        } -CompletedCallback {
            param($data)

            try {
                $reportContent = $data.Results -join "`r`n"

                # Save detailed report
                $reportPath = "$env:USERPROFILE\Desktop\WDCA_DC_Upgrade_Prep_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                Set-Content -Path $reportPath -Value $reportContent -Encoding UTF8

                # Determine message type
                $messageType = if ($data.Errors -gt 0) {
                    [System.Windows.MessageBoxImage]::Error
                } elseif ($data.ForestPrepRequired -or $data.DomainPrepRequired -or $data.Warnings -gt 2) {
                    [System.Windows.MessageBoxImage]::Warning
                } else {
                    [System.Windows.MessageBoxImage]::Information
                }

                $title = "WDCA - DC Upgrade Preparation ($($data.ReadinessLevel))"

                # Create summary message
                $summaryMessage = "Domain Controller Upgrade Preparation Complete`n`n"
                $summaryMessage += "Target: Windows Server $($data.TargetVersion)`n"
                $summaryMessage += "Readiness: $($data.ReadinessScore)/100 ($($data.ReadinessLevel))`n"
                $summaryMessage += "FSMO Roles: $($data.FSMORoles)`n"
                $summaryMessage += "Forest Prep: $(if ($data.ForestPrepRequired) { 'REQUIRED' } else { 'Not needed' })`n"
                $summaryMessage += "Domain Prep: $(if ($data.DomainPrepRequired) { 'REQUIRED' } else { 'Not needed' })`n"
                $summaryMessage += "Errors: $($data.Errors) | Warnings: $($data.Warnings)`n`n"

                if ($data.Errors -eq 0 -and !$data.ForestPrepRequired -and !$data.DomainPrepRequired) {
                    $summaryMessage += "DC ready for upgrade after backup"
                } elseif ($data.Errors -eq 0) {
                    $summaryMessage += "Complete ADPREP operations first"
                } else {
                    $summaryMessage += "Critical issues must be resolved"
                }

                $summaryMessage += "`n`nDetailed report: $reportPath"

                [System.Windows.MessageBox]::Show($summaryMessage, $title, [System.Windows.MessageBoxButton]::OK, $messageType)

                Write-Logger "DC upgrade preparation completed for Windows Server $($data.TargetVersion)" "SUCCESS"

            } catch {
                Write-Logger "Error in DC upgrade preparation callback: $($_.Exception.Message)" "ERROR"
                [System.Windows.MessageBox]::Show(
                    "DC preparation completed but error processing results: $($_.Exception.Message)",
                    "WDCA - Processing Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
            }
        } -OperationName "DC Upgrade Preparation (Server $TargetWindowsVersion)"

    } catch {
        Write-Logger "Error in DC Upgrade Preparation: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start DC upgrade preparation: $($_.Exception.Message)",
            "WDCA - DC Preparation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
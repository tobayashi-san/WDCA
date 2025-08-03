function Invoke-FSMORoleAnalysis {
    <#
    .SYNOPSIS
        Analyzes FSMO roles in the Active Directory environment
    #>

    Write-Logger "Starting FSMO Role Analysis" "INFO"

    try {
        $analysisScript = {
            $results = @()

            try {
                Import-Module ActiveDirectory -ErrorAction Stop

                $results += "=== FSMO ROLES ANALYSIS ==="
                $results += "Analysis Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $results += ""

                # Get Forest and Domain info
                $forest = Get-ADForest
                $domain = Get-ADDomain
                $currentDC = "$($env:COMPUTERNAME).$($domain.DNSRoot)"

                # Forest-wide FSMO Roles
                $results += "=== FOREST-WIDE FSMO ROLES ==="
                $results += "Schema Master: $($forest.SchemaMaster)"
                $results += "Domain Naming Master: $($forest.DomainNamingMaster)"
                $results += ""

                # Domain FSMO Roles
                $results += "=== DOMAIN FSMO ROLES ==="
                $results += "PDC Emulator: $($domain.PDCEmulator)"
                $results += "RID Master: $($domain.RIDMaster)"
                $results += "Infrastructure Master: $($domain.InfrastructureMaster)"
                $results += ""

                # Check if current DC holds any FSMO roles
                $currentDCRoles = @()
                if ($forest.SchemaMaster -eq $currentDC) { $currentDCRoles += "Schema Master" }
                if ($forest.DomainNamingMaster -eq $currentDC) { $currentDCRoles += "Domain Naming Master" }
                if ($domain.PDCEmulator -eq $currentDC) { $currentDCRoles += "PDC Emulator" }
                if ($domain.RIDMaster -eq $currentDC) { $currentDCRoles += "RID Master" }
                if ($domain.InfrastructureMaster -eq $currentDC) { $currentDCRoles += "Infrastructure Master" }

                $results += "=== CURRENT DC ROLE ANALYSIS ==="
                $results += "Current DC: $currentDC"
                if ($currentDCRoles.Count -gt 0) {
                    $results += "FSMO Roles on this DC: $($currentDCRoles.Count)"
                    foreach ($role in $currentDCRoles) {
                        $results += "  - $role"
                    }
                    $results += ""
                    $results += "UPGRADE IMPACT:"
                    $results += "- This DC holds critical FSMO roles"
                    $results += "- Consider transferring roles before upgrade"
                    $results += "- Extended downtime will affect these services"
                } else {
                    $results += "FSMO Roles on this DC: None"
                    $results += "Safe for upgrade (no FSMO roles)"
                }
                $results += ""

                # Get all DCs in domain
                $results += "=== ALL DOMAIN CONTROLLERS ==="
                $allDCs = Get-ADDomainController -Filter *
                foreach ($dc in $allDCs) {
                    $results += "DC: $($dc.Name) ($($dc.IPv4Address))"
                    $results += "  Site: $($dc.Site)"
                    $results += "  OS: $($dc.OperatingSystem)"
                    $results += "  GC: $(if ($dc.IsGlobalCatalog) { 'Yes' } else { 'No' })"
                    $results += ""
                }

                # FSMO Transfer Commands
                $results += "=== FSMO TRANSFER COMMANDS ==="
                $results += "To transfer roles FROM this DC to another DC:"
                $results += ""
                $results += "# Connect to target DC first:"
                $results += "netdom query fsmo"
                $results += ""
                $results += "# Transfer individual roles:"
                if ($currentDCRoles -contains "Schema Master") {
                    $results += "Move-ADDirectoryServerOperationMasterRole -Identity <TargetDC> -OperationMasterRole SchemaMaster"
                }
                if ($currentDCRoles -contains "Domain Naming Master") {
                    $results += "Move-ADDirectoryServerOperationMasterRole -Identity <TargetDC> -OperationMasterRole DomainNamingMaster"
                }
                if ($currentDCRoles -contains "PDC Emulator") {
                    $results += "Move-ADDirectoryServerOperationMasterRole -Identity <TargetDC> -OperationMasterRole PDCEmulator"
                }
                if ($currentDCRoles -contains "RID Master") {
                    $results += "Move-ADDirectoryServerOperationMasterRole -Identity <TargetDC> -OperationMasterRole RIDMaster"
                }
                if ($currentDCRoles -contains "Infrastructure Master") {
                    $results += "Move-ADDirectoryServerOperationMasterRole -Identity <TargetDC> -OperationMasterRole InfrastructureMaster"
                }

                if ($currentDCRoles.Count -gt 0) {
                    $results += ""
                    $results += "# Transfer all roles at once:"
                    $results += "Move-ADDirectoryServerOperationMasterRole -Identity <TargetDC> -OperationMasterRole SchemaMaster,DomainNamingMaster,PDCEmulator,RIDMaster,InfrastructureMaster"
                }

            } catch {
                $results += "ERROR: $($_.Exception.Message)"
            }

            return $results
        }

        Start-AsyncOperation -ScriptBlock $analysisScript -CompletedCallback {
            param($data)

            $reportContent = $data -join "`r`n"
            $reportPath = "$env:USERPROFILE\Desktop\WDCA_FSMO_Analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            Set-Content -Path $reportPath -Value $reportContent -Encoding UTF8

            [System.Windows.MessageBox]::Show(
                "FSMO Role Analysis completed.`n`nReport saved to:`n$reportPath",
                "WDCA - FSMO Analysis Complete",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
        } -OperationName "FSMO Role Analysis"

    } catch {
        Write-Logger "Error in FSMO Analysis: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start FSMO analysis: $($_.Exception.Message)",
            "WDCA - FSMO Analysis Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

function Invoke-ADReplicationCheck {
    <#
    .SYNOPSIS
        Performs comprehensive AD replication health check
    #>

    Write-Logger "Starting AD Replication Check" "INFO"

    try {
        $replicationScript = {
            $results = @()

            try {
                Import-Module ActiveDirectory -ErrorAction Stop

                $results += "=== AD REPLICATION HEALTH CHECK ==="
                $results += "Check Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $results += "Current DC: $env:COMPUTERNAME"
                $results += ""

                # Replication Partners
                $results += "=== REPLICATION PARTNERS ==="
                $partners = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction Stop
                $results += "Total Partners: $($partners.Count)"
                $results += ""

                $healthyPartners = 0
                $errorPartners = 0

                foreach ($partner in $partners) {
                    $results += "Partner: $($partner.Partner)"
                    $results += "  Partition: $($partner.Partition)"
                    $results += "  Last Replication: $($partner.LastReplicationAttempt)"
                    $results += "  Last Success: $($partner.LastReplicationSuccess)"
                    $results += "  Result: $($partner.LastReplicationResult)"

                    if ($partner.LastReplicationResult -eq 0) {
                        $results += "  Status: HEALTHY"
                        $healthyPartners++
                    } else {
                        $results += "  Status: ERROR"
                        $errorPartners++
                    }
                    $results += ""
                }

                $results += "=== REPLICATION SUMMARY ==="
                $results += "Healthy Partners: $healthyPartners"
                $results += "Partners with Errors: $errorPartners"
                $results += ""

                # Replication Failures
                $results += "=== REPLICATION FAILURES ==="
                try {
                    $failures = Get-ADReplicationFailure -Target $env:COMPUTERNAME -ErrorAction SilentlyContinue
                    if ($failures) {
                        $results += "Active Failures: $($failures.Count)"
                        foreach ($failure in $failures) {
                            $results += "Failure: $($failure.Server) - $($failure.LastError)"
                        }
                    } else {
                        $results += "No active replication failures"
                    }
                } catch {
                    $results += "Could not check replication failures: $($_.Exception.Message)"
                }
                $results += ""

                # Replication Queue
                $results += "=== REPLICATION QUEUE ==="
                try {
                    $queue = Get-ADReplicationQueueOperation -Server $env:COMPUTERNAME -ErrorAction SilentlyContinue
                    if ($queue) {
                        $results += "Queued Operations: $($queue.Count)"
                        foreach ($op in $queue | Select-Object -First 5) {
                            $results += "Operation: $($op.PartitionName) - $($op.OperationType)"
                        }
                        if ($queue.Count -gt 5) {
                            $results += "... and $($queue.Count - 5) more operations"
                        }
                    } else {
                        $results += "No operations in replication queue"
                    }
                } catch {
                    $results += "Could not check replication queue: $($_.Exception.Message)"
                }
                $results += ""

                # DCDiag equivalent checks
                $results += "=== DCDIAG-STYLE CHECKS ==="
                $results += "Testing critical replication functions..."
                $results += ""

                # Connectivity test
                $results += "Connectivity Test:"
                try {
                    $domain = Get-ADDomain
                    $otherDCs = Get-ADDomainController -Filter "Name -ne '$env:COMPUTERNAME'"

                    foreach ($dc in $otherDCs | Select-Object -First 3) {
                        if (Test-Connection -ComputerName $dc.IPv4Address -Count 1 -Quiet) {
                            $results += "  $($dc.Name) - Reachable"
                        } else {
                            $results += "  $($dc.Name) - Not reachable"
                        }
                    }
                } catch {
                    $results += "  Could not test connectivity: $($_.Exception.Message)"
                }
                $results += ""

                # Recommendations
                $results += "=== RECOMMENDATIONS ==="
                if ($errorPartners -gt 0) {
                    $results += "CRITICAL: Fix replication errors before DC upgrade"
                    $results += "- Run: repadmin /showrepl for detailed error information"
                    $results += "- Run: repadmin /replicate to force replication"
                    $results += "- Check network connectivity between DCs"
                } else {
                    $results += "Replication appears healthy"
                    $results += "- Safe to proceed with DC upgrade planning"
                }

                $results += ""
                $results += "Manual commands for further analysis:"
                $results += "- repadmin /replsummary - Overall replication status"
                $results += "- repadmin /showrepl - Detailed replication info"
                $results += "- dcdiag /test:replications - Full replication test"
                $results += "- Get-ADReplicationUpToDatenessVectorTable - Vector table"

            } catch {
                $results += "ERROR: $($_.Exception.Message)"
            }

            return $results
        }

        Start-AsyncOperation -ScriptBlock $replicationScript -CompletedCallback {
            param($data)

            $reportContent = $data -join "`r`n"
            $reportPath = "$env:USERPROFILE\Desktop\WDCA_Replication_Check_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            Set-Content -Path $reportPath -Value $reportContent -Encoding UTF8

            [System.Windows.MessageBox]::Show(
                "AD Replication Check completed.`n`nReport saved to:`n$reportPath",
                "WDCA - Replication Check Complete",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
        } -OperationName "AD Replication Check"

    } catch {
        Write-Logger "Error in Replication Check: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to start replication check: $($_.Exception.Message)",
            "WDCA - Replication Check Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

#########################################################################
#                                                                       #
# Windows Deployment & Configuration Assistant (WDCA)                  #
# Version: #{replaceme}                                                 #
# Author: Tobayashi-san                                                 #
# License: MIT                                                          #
#                                                                       #
#########################################################################

param(
    [string]$Config,
    [switch]$Run,
    [switch]$Debug
)

# Admin check and restart
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "WDCA needs to run as Administrator. Attempting to restart..." -ForegroundColor Yellow

    try {
        $argList = @()
        $PSBoundParameters.GetEnumerator() | ForEach-Object {
            $argList += if ($_.Value -is [switch] -and $_.Value) {
                "-$($_.Key)"
            } elseif ($_.Value) {
                "-$($_.Key) '$($_.Value)'"
            }
        }

        $script = if ($PSCommandPath) {
            "& `'$PSCommandPath`' $($argList -join ' ')"
        } else {
            $MyInvocation.MyCommand.Definition
        }

        $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
        $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { $powershellCmd }

        if ($processCmd -eq "wt.exe") {
            Start-Process $processCmd -ArgumentList "$powershellCmd -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        } else {
            Start-Process $processCmd -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        }

        exit 0
    }
    catch {
        Write-Host "Failed to restart as administrator. Please run PowerShell as Administrator manually." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Set execution policy and initialize
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
$Host.UI.RawUI.WindowTitle = "WDCA (Admin)"

# Initialize sync hashtable
$global:sync = [Hashtable]::Synchronized(@{})
$global:sync.PSScriptRoot = $PSScriptRoot
$global:sync.configs = @{}
$global:sync.ProcessRunning = $false
$global:sync.logLevel = if ($Debug) { "DEBUG" } else { "INFO" }

# Setup logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logdir = "$env:LOCALAPPDATA\WDCA\logs"
[System.IO.Directory]::CreateDirectory($logdir) | Out-Null
$global:sync.logFile = "$logdir\WDCA_$timestamp.log"

# Store parameters
$global:sync.Config = $Config
$global:sync.Run = $Run
$global:sync.Debug = $Debug

# Welcome message
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Windows Deployment & Configuration Assistant (WDCA)" -ForegroundColor Yellow
Write-Host "Version: #{replaceme}" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Basic checks
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "PowerShell 5.0 or higher required. Current: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

try {
    $null = Get-Command winget -ErrorAction Stop
    Write-Host "[OK] WinGet is available" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] WinGet not available. Some features limited." -ForegroundColor Yellow
}

try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Write-Host "[OK] WPF Framework available" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] WPF Framework not available. Cannot start GUI." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Initialization completed." -ForegroundColor Green
Write-Host ""
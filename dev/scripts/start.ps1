#########################################################################
#                                                                       #
# Windows Deployment & Configuration Assistant (WDCA)                   #
# Version: (auto)                                                       #
# Author: Tobayashi-san                                                  #
# License: MIT                                                           #
#                                                                       #
#########################################################################

param(
    [string]$Config,
    [switch]$Run,
    [switch]$Debug
)

# Version automatisch aus Datum setzen
$script:Version = (Get-Date -Format "yy.MM.dd")

# Admin check and restart
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "WDCA needs to run as Administrator. Attempting to restart..." -ForegroundColor Yellow

    try {
        $argList = @()
        foreach ($param in $PSBoundParameters.GetEnumerator()) {
            if ($param.Value -is [switch] -and $param.Value) {
                $argList += "-$($param.Key)"
            }
            elseif ($null -ne $param.Value -and $param.Value -ne "") {
                $argList += "-$($param.Key) `"$($param.Value)`""
            }
        }

        # Absoluten Skriptpfad holen (immer die Datei, nicht den Ordner)
        $scriptPath = if ($MyInvocation.MyCommand.Path) {
            $MyInvocation.MyCommand.Path
        } elseif ($PSCommandPath) {
            $PSCommandPath
        } else {
            throw "Cannot determine script path for restart."
        }

        $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
        $processCmd    = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { $powershellCmd }

        $arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" $($argList -join ' ')"

        if ($processCmd -eq "wt.exe") {
            Start-Process $processCmd -ArgumentList "$powershellCmd $arguments" -Verb RunAs
        }
        else {
            Start-Process $processCmd -ArgumentList $arguments -Verb RunAs
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
$script:sync = [Hashtable]::Synchronized(@{
    PSScriptRoot   = $PSScriptRoot
    configs        = @{}
    ProcessRunning = $false
    logLevel       = if ($Debug) { "DEBUG" } else { "INFO" }
})

# Setup logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logdir    = "$env:LOCALAPPDATA\WDCA\logs"
[System.IO.Directory]::CreateDirectory($logdir) | Out-Null
$script:sync.logFile = "$logdir\WDCA_$timestamp.log"

# Store parameters
$script:sync.Config = $Config
$script:sync.Run    = $Run
$script:sync.Debug  = $Debug

# Welcome message
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Windows Deployment & Configuration Assistant (WDCA)" -ForegroundColor Yellow
Write-Host "Version: $script:Version" -ForegroundColor Green
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
    $script:sync.GUIAvailable = $true
}
catch {
    Write-Host "[WARNING] WPF Framework not available. Falling back to CLI mode." -ForegroundColor Yellow
    $script:sync.GUIAvailable = $false
}

Write-Host "Initialization completed." -ForegroundColor Green
Write-Host ""

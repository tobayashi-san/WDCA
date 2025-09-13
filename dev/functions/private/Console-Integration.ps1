
function Set-ConsoleEventHandlers {
    try {
        if ($script:sync.WPFToggleConsole)     { $script:sync.WPFToggleConsole.Add_Click({ Toggle-Console }) }
        if ($script:sync.WPFClearConsole)      { $script:sync.WPFClearConsole.Add_Click({ Clear-ConsoleOutput }) }
        if ($script:sync.WPFExecuteCommand)    { $script:sync.WPFExecuteCommand.Add_Click({ Execute-ConsoleCommand }) }
        if ($script:sync.WPFStopConsoleCommand){ $script:sync.WPFStopConsoleCommand.Add_Click({ Stop-ConsoleCommand }) }

        if ($script:sync.WPFConsoleInput) {
            $script:sync.WPFConsoleInput.Add_KeyDown({
                param($sender, $e)
                try {
                    switch ($e.Key) {
                        "Return" { Execute-ConsoleCommand; $e.Handled = $true }
                        "Up"     { Navigate-CommandHistory -Direction "Up"; $e.Handled = $true }
                        "Down"   { Navigate-CommandHistory -Direction "Down"; $e.Handled = $true }
                        "Escape" { $script:sync.WPFConsoleInput.Text = ""; $e.Handled = $true }
                    }
                }
                catch { Write-Logger "Error in console input handler: $($_.Exception.Message)" "ERROR" }
            })
        }
        Write-Logger "Console event handlers set" "DEBUG"
    }
    catch { Write-Logger "Error setting console event handlers: $($_.Exception.Message)" "ERROR" }
}

function Toggle-Console {
    try {
        if ($script:ConsoleState.IsVisible) {
            $script:sync.ConsoleColumn.Width = "0"
            $script:sync.ConsolePanel.Visibility = "Collapsed"
            $script:sync.WPFToggleConsole.Content = "Show Console"
            $script:ConsoleState.IsVisible = $false
            Write-Logger "Console hidden" "DEBUG"
        }
        else {
            $script:sync.ConsoleColumn.Width = "400"
            $script:sync.ConsolePanel.Visibility = "Visible"
            $script:sync.WPFToggleConsole.Content = "Hide Console"
            $script:ConsoleState.IsVisible = $true
            try { $script:sync.WPFConsoleInput.Focus() } catch {}
            Write-Logger "Console shown" "DEBUG"
        }
        Update-ConsoleStatus "Ready"
    }
    catch { Write-Logger "Error toggling console: $($_.Exception.Message)" "ERROR" }
}

function Execute-ConsoleCommand {
    try {
        $command = $script:sync.WPFConsoleInput.Text.Trim()
        if ([string]::IsNullOrEmpty($command)) { return }
        if ($script:ConsoleState.IsRunning) {
            Add-ConsoleOutput "Command is running. Use Stop button or wait for completion." "Warning"
            return
        }

        $script:ConsoleState.CommandHistory += $command
        $script:ConsoleState.HistoryIndex = -1
        $script:sync.WPFConsoleInput.Text = ""
        Add-ConsoleOutput "PS> $command" "Input"

        Update-ConsoleStatus "Executing: $command"
        $script:ConsoleState.IsRunning = $true
        Execute-ConsoleCommand-Simple -Command $command
    }
    catch {
        Write-Logger "Error executing console command: $($_.Exception.Message)" "ERROR"
        Add-ConsoleOutput "Error: $($_.Exception.Message)" "Error"
        $script:ConsoleState.IsRunning = $false
    }
}

function Execute-ConsoleCommand-Simple {
    param([string]$Command)
    try {
        $powershell = [powershell]::Create()
        $powershell.Runspace = $script:ConsoleRunspace
        $scriptBlock = {
            param($cmd)
            try {
                $result = Invoke-Expression $cmd 2>&1
                return @{ Success=$true; Output=$result; ExitCode=$LASTEXITCODE }
            }
            catch { return @{ Success=$false; Error=$_.Exception.Message; Output=@() } }
        }
        $powershell.AddScript($scriptBlock).AddParameter("cmd",$Command)
        $asyncResult = $powershell.BeginInvoke()
        $script:ConsoleState.CurrentCommand = @{
            PowerShell = $powershell; AsyncResult=$asyncResult; Command=$Command; StartTime=Get-Date
        }
        Start-SimpleCompletionChecker
    }
    catch {
        Write-Logger "Error starting command: $($_.Exception.Message)" "ERROR"
        Add-ConsoleOutput "Failed to execute: $($_.Exception.Message)" "Error"
        $script:ConsoleState.IsRunning = $false
        Update-ConsoleStatus "Ready"
    }
}

function Start-SimpleCompletionChecker {
    try {
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Add_Tick({
            try {
                if ($script:ConsoleState.CurrentCommand -and $script:ConsoleState.CurrentCommand.AsyncResult.IsCompleted) {
                    $results = $script:ConsoleState.CurrentCommand.PowerShell.EndInvoke($script:ConsoleState.CurrentCommand.AsyncResult)
                    $duration = (Get-Date) - $script:ConsoleState.CurrentCommand.StartTime
                    $durationText = "$([math]::Round($duration.TotalMilliseconds))ms"
                    if ($results.Output) { foreach ($out in $results.Output) { Add-ConsoleOutput $out "Output" } }
                    if ($results.Success) { Add-ConsoleOutput "Command completed successfully in $durationText" "Success" }
                    else {
                        Add-ConsoleOutput "Command failed in $durationText" "Error"
                        if ($results.Error) { Add-ConsoleOutput "Error: $($results.Error)" "Error" }
                    }
                    Complete-ConsoleExecution; $this.Stop()
                }
            }
            catch { Write-Logger "Error in completion checker: $($_.Exception.Message)" "ERROR"; Complete-ConsoleExecution; $this.Stop() }
        })
        $timer.Start()
    }
    catch { Write-Logger "Error starting completion checker: $($_.Exception.Message)" "ERROR"; Complete-ConsoleExecution }
}

function Complete-ConsoleExecution {
    try {
        if ($script:ConsoleState.CurrentCommand?.PowerShell) {
            try { $script:ConsoleState.CurrentCommand.PowerShell.Dispose() }
            catch { Write-Logger "Error disposing PowerShell: $($_.Exception.Message)" "WARNING" }
        }
        $script:ConsoleState.CurrentCommand = $null
        $script:ConsoleState.IsRunning = $false
        Update-ConsoleStatus "Ready"
    }
    catch { Write-Logger "Error completing console execution: $($_.Exception.Message)" "ERROR" }
}

function Update-ConsoleText {
    param([string]$Text)
    try {
        if ($script:sync.WPFConsoleOutput) {
            $timestamp = Get-Date -Format "HH:mm:ss"
            $script:sync.WPFConsoleOutput.AppendText("[$timestamp] $Text`r`n")
            if ($script:sync.ConsoleScrollViewer) { $script:sync.ConsoleScrollViewer.ScrollToEnd() }
        }
    }
    catch { Write-Logger "Error updating console text: $($_.Exception.Message)" "ERROR" }
}

function Clear-ConsoleOutput {
    try {
        if ($script:sync.WPFConsoleOutput) {
            $script:sync.WPFConsoleOutput.Text = "Windows PowerShell Console`r`nCopyright (C) Microsoft Corporation. All rights reserved.`r`n`r`nPS C:\> "
        }
        Update-ConsoleStatus "Console cleared"
        Write-Logger "Console output cleared" "DEBUG"
    }
    catch { Write-Logger "Error clearing console output: $($_.Exception.Message)" "ERROR" }
}

function Update-ConsoleStatus {
    param([string]$Status)
    try {
        if ($script:sync.WPFConsoleStatus) {
            $action = { $script:sync.WPFConsoleStatus.Text = $Status }
            if ($script:sync.Form.Dispatcher.CheckAccess()) { & $action }
            else { $script:sync.Form.Dispatcher.BeginInvoke([System.Action]$action) | Out-Null }
        }
    }
    catch { Write-Logger "Error updating console status: $($_.Exception.Message)" "ERROR" }
}

function Navigate-CommandHistory {
    param([string]$Direction)
    try {
        $history = $script:ConsoleState.CommandHistory
        if ($history.Count -eq 0) { return }
        if ($Direction -eq "Up"   -and $script:ConsoleState.HistoryIndex -lt ($history.Count - 1)) { $script:ConsoleState.HistoryIndex++ }
        if ($Direction -eq "Down" -and $script:ConsoleState.HistoryIndex -gt -1) { $script:ConsoleState.HistoryIndex-- }
        if ($script:ConsoleState.HistoryIndex -ge 0) {
            $cmd = $history[$history.Count-1-$script:ConsoleState.HistoryIndex]
            $script:sync.WPFConsoleInput.Text = $cmd
            $script:sync.WPFConsoleInput.CaretIndex = $cmd.Length
        } else { $script:sync.WPFConsoleInput.Text = "" }
    }
    catch { Write-Logger "Error navigating command history: $($_.Exception.Message)" "ERROR" }
}

function Stop-ConsoleCommand {
    try {
        if ($script:ConsoleState.IsRunning) {
            Write-Logger "Stopping console command" "WARNING"
            try {
                $script:ConsoleState.CurrentCommand?.PowerShell.Stop()
                Add-ConsoleOutput "Command stopped by user" "Warning"
            }
            catch { Add-ConsoleOutput "Error stopping command: $($_.Exception.Message)" "Error" }
            finally { Complete-ConsoleExecution }
        }
        else { Add-ConsoleOutput "No command currently running" "Info" }
    }
    catch { Write-Logger "Error stopping console command: $($_.Exception.Message)" "ERROR" }
}

function Close-WDCAConsole {
    try {
        Write-Logger "Closing WDCA console..." "INFO"
        if ($script:ConsoleState.IsRunning) { Complete-ConsoleExecution }
        if ($script:ConsoleRunspace) {
            try { $script:ConsoleRunspace.Close(); $script:ConsoleRunspace.Dispose(); $script:ConsoleRunspace=$null }
            catch { Write-Logger "Error closing console runspace: $($_.Exception.Message)" "WARNING" }
        }
        Write-Logger "Console closed and cleaned up" "INFO"
    }
    catch { Write-Logger "Error closing console: $($_.Exception.Message)" "ERROR" }
}


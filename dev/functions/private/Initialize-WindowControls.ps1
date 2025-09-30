function Initialize-WindowControls {
    <#
    .SYNOPSIS
        Initializes window control event handlers for standard Windows controls
    #>

    try {

        if ($global:sync.Form) {
            # Window state change events (optional)
            $global:sync.Form.Add_StateChanged({
                try {
                    $state = $global:sync.Form.WindowState
                    Write-Logger "Window state changed to: $state" "DEBUG"
                }
                catch {
                    Write-Logger "Error in StateChanged event: $($_.Exception.Message)" "DEBUG"
                }
            })

            # Window closing event (wichtig für Cleanup)
            $global:sync.Form.Add_Closing({
                try {
                    Write-Logger "Application closing" "INFO"
                    Stop-AllAsyncOperations
                }
                catch {
                    Write-Logger "Error during window close cleanup: $($_.Exception.Message)" "ERROR"
                }
            })
        }
    }
    catch {
        Write-Logger "Error initializing window controls: $($_.Exception.Message)" "ERROR"
    }
}
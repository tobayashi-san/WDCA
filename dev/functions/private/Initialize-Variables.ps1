function Initialize-WDCAVariables {
    <#
    .SYNOPSIS
        Safely creates variables for all named XAML elements
    #>

    try {
        Write-Logger "Creating XAML element variables..." "INFO"

        # Get all named elements from XAML
        $namedElements = $XAML.SelectNodes("//*[@Name]")
        $elementCount = 0
        $duplicateCount = 0

        foreach ($element in $namedElements) {
            $elementName = $element.Name

            try {
                # Check if variable already exists
                if ($global:sync.ContainsKey($elementName)) {
                    Write-Logger "Variable $elementName already exists, skipping..." "DEBUG"
                    $duplicateCount++
                    continue
                }

                # Find the actual UI element
                $uiElement = $global:sync.Form.FindName($elementName)

                if ($uiElement) {
                    $global:sync[$elementName] = $uiElement
                    $elementCount++
                    Write-Logger "Created variable: $elementName" "DEBUG"
                } else {
                    Write-Logger "UI element not found: $elementName" "WARNING"
                }
            }
            catch {
                Write-Logger "Error creating variable for $elementName`: $($_.Exception.Message)" "WARNING"
            }
        }

        Write-Logger "Created $elementCount UI element variables ($duplicateCount duplicates skipped)" "INFO"
    }
    catch {
        Write-Logger "Error initializing XAML variables: $($_.Exception.Message)" "ERROR"
    }
}

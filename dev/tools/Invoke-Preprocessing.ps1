function Invoke-Preprocessing {
    <#
    .SYNOPSIS
        Preprocesses PowerShell files for compilation
    
    .DESCRIPTION
        Handles code formatting, validation, and preprocessing tasks for the WDCA build process
    
    .PARAMETER WorkingDir
        The working directory containing source files
    
    .PARAMETER ExcludedFiles
        Array of files/patterns to exclude from preprocessing
    
    .PARAMETER ProgressStatusMessage
        Status message to display during preprocessing
    
    .EXAMPLE
        Invoke-Preprocessing -WorkingDir "C:\WDCA" -ExcludedFiles @('*.png', '.git*') -ProgressStatusMessage "Processing files..."
    #>
    
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDir,
        
        [Parameter(Mandatory = $false)]
        [array]$ExcludedFiles = @(),
        
        [Parameter(Mandatory = $false)]
        [string]$ProgressStatusMessage = "Preprocessing files..."
    )
    
    try {
        Write-Host $ProgressStatusMessage -ForegroundColor Yellow
        
        # Initialize preprocessing variables
        $processedFiles = 0
        $totalFiles = 0
        $preprocessorHashes = @{}
        $hashFile = Join-Path $WorkingDir ".preprocessor_hashes.json"
        
        # Load existing hashes if available
        if (Test-Path $hashFile) {
            try {
                $existingHashes = Get-Content $hashFile -Raw | ConvertFrom-Json
                if ($existingHashes) {
                    $existingHashes.PSObject.Properties | ForEach-Object {
                        $preprocessorHashes[$_.Name] = $_.Value
                    }
                }
            }
            catch {
                Write-Warning "Could not load existing preprocessor hashes: $($_.Exception.Message)"
            }
        }
        
        # Get all PowerShell files for processing
        $sourceFiles = @()
        $searchPaths = @("functions", "scripts", "config")
        
        foreach ($path in $searchPaths) {
            $fullPath = Join-Path $WorkingDir $path
            if (Test-Path $fullPath) {
                $files = Get-ChildItem -Path $fullPath -Recurse -File -Include "*.ps1", "*.json" | Where-Object {
                    $relativePath = $_.FullName.Replace($WorkingDir, "").TrimStart('\', '/')
                    $isExcluded = $false
                    
                    foreach ($excludePattern in $ExcludedFiles) {
                        if ($relativePath -like $excludePattern) {
                            $isExcluded = $true
                            break
                        }
                    }
                    
                    -not $isExcluded
                }
                $sourceFiles += $files
            }
        }
        
        $totalFiles = $sourceFiles.Count
        Write-Host "Found $totalFiles files to preprocess" -ForegroundColor Green
        
        foreach ($file in $sourceFiles) {
            $processedFiles++
            $relativePath = $file.FullName.Replace($WorkingDir, "").TrimStart('\', '/')
            $progressPercent = [math]::Round(($processedFiles / $totalFiles) * 100)
            
            Write-Progress -Activity "Preprocessing Files" -Status "Processing $relativePath" -PercentComplete $progressPercent
            
            try {
                # Calculate file hash to check if processing is needed
                $currentHash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
                
                if ($preprocessorHashes[$relativePath] -eq $currentHash) {
                    # File hasn't changed, skip processing
                    continue
                }
                
                # Process based on file type
                switch ($file.Extension.ToLower()) {
                    ".ps1" {
                        Invoke-PowerShellPreprocessing -FilePath $file.FullName
                    }
                    ".json" {
                        Invoke-JsonValidation -FilePath $file.FullName
                    }
                }
                
                # Update hash after successful processing
                $preprocessorHashes[$relativePath] = $currentHash
                
            }
            catch {
                Write-Warning "Error preprocessing $relativePath`: $($_.Exception.Message)"
            }
        }
        
        Write-Progress -Activity "Preprocessing Files" -Completed
        
        # Save updated hashes
        try {
            $preprocessorHashes | ConvertTo-Json -Depth 2 | Set-Content -Path $hashFile -Encoding UTF8
        }
        catch {
            Write-Warning "Could not save preprocessor hashes: $($_.Exception.Message)"
        }
        
        Write-Host "Preprocessing completed. Processed $processedFiles files." -ForegroundColor Green
        
    }
    catch {
        Write-Error "Preprocessing failed: $($_.Exception.Message)"
        throw
    }
}

function Invoke-PowerShellPreprocessing {
    <#
    .SYNOPSIS
        Preprocesses PowerShell files for code quality and formatting
    
    .PARAMETER FilePath
        Path to the PowerShell file to preprocess
    #>
    
    param([string]$FilePath)
    
    try {
        $content = Get-Content -Path $FilePath -Raw
        $originalContent = $content
        
        # Basic syntax validation
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
        
        if ($errors.Count -gt 0) {
            Write-Warning "Syntax errors found in $FilePath"
            foreach ($error in $errors) {
                Write-Warning "  Line $($error.Extent.StartLineNumber): $($error.Message)"
            }
        }
        
        # Remove excessive blank lines (more than 2 consecutive)
        $content = $content -replace '(\r?\n\s*){3,}', "`r`n`r`n"
        
        # Ensure consistent line endings
        $content = $content -replace '\r\n', "`n" -replace '\r', "`n" -replace '\n', "`r`n"
        
        # Remove trailing whitespace
        $lines = $content -split '\r?\n'
        $cleanedLines = $lines | ForEach-Object { $_.TrimEnd() }
        $content = $cleanedLines -join "`r`n"
        
        # Only write back if content changed
        if ($content -ne $originalContent) {
            Set-Content -Path $FilePath -Value $content -Encoding UTF8 -NoNewline
        }
    }
    catch {
        Write-Warning "Error preprocessing PowerShell file $FilePath`: $($_.Exception.Message)"
    }
}

function Invoke-JsonValidation {
    <#
    .SYNOPSIS
        Validates JSON files for proper formatting
    
    .PARAMETER FilePath
        Path to the JSON file to validate
    #>
    
    param([string]$FilePath)
    
    try {
        $content = Get-Content -Path $FilePath -Raw
        
        # Skip empty files
        if ([string]::IsNullOrWhiteSpace($content)) {
            return
        }
        
        # Validate JSON syntax
        try {
            $jsonObject = $content | ConvertFrom-Json
            
            # Re-format JSON with consistent formatting
            $formattedJson = $jsonObject | ConvertTo-Json -Depth 10 -Compress:$false
            
            # Only write back if content changed significantly
            $normalizedOriginal = ($content -replace '\s+', ' ').Trim()
            $normalizedFormatted = ($formattedJson -replace '\s+', ' ').Trim()
            
            if ($normalizedOriginal -ne $normalizedFormatted) {
                Set-Content -Path $FilePath -Value $formattedJson -Encoding UTF8
            }
        }
        catch {
            Write-Warning "JSON syntax error in $FilePath`: $($_.Exception.Message)"
        }
    }
    catch {
        Write-Warning "Error validating JSON file $FilePath`: $($_.Exception.Message)"
    }
}
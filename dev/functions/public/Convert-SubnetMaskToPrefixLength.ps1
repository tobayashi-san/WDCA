function Convert-SubnetMaskToPrefixLength {
    param([string]$SubnetMask)
    try {
        $mask = [System.Net.IPAddress]::Parse($SubnetMask)
        $bytes = $mask.GetAddressBytes()
        $binaryString = ""

        # Convert all bytes to binary string
        foreach ($byte in $bytes) {
            $binaryString += [Convert]::ToString($byte, 2).PadLeft(8, '0')
        }

        # Count consecutive 1s from the left
        $prefixLength = 0
        for ($i = 0; $i -lt $binaryString.Length; $i++) {
            if ($binaryString[$i] -eq '1') {
                $prefixLength++
            } else {
                break
            }
        }

        # Validate that all remaining bits are 0
        $remainingBits = $binaryString.Substring($prefixLength)
        if ($remainingBits -match '1') {
            throw "Invalid subnet mask - non-contiguous bits"
        }

        return $prefixLength
    }
    catch {
        Write-Logger "Error converting subnet mask '$SubnetMask': $($_.Exception.Message)" "WARNING"
        return 24  # Default to /24
    }
}
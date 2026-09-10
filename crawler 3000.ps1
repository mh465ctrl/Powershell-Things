function Start-InfiniteParallelScan {
    param (
        [int]$MaxThreads = 30
    )
    
    $tlds = @(".com", ".ru", ".cn", ".net", ".org", ".info", ".biz")
    $characters = [char[]]'abcdefghijklmnopqrstuvwxyz'

    Write-Host "[*] Starting PowerShell crawler with $MaxThreads workers..." -ForegroundColor Cyan
    Write-Host "[*] Saving live hits to 'live_results.txt'. Press Ctrl+C to stop.`n" -ForegroundColor Yellow

    while ($true) {
        $urlBatch = @()

        # Build a mixed batch of IPs and Domains
        while ($urlBatch.Count -lt $MaxThreads) {
            if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
                # Generate Domain
                $length = Get-Random -Minimum 5 -Maximum 11
                $domain = (-join (1..$length | ForEach-Object { $characters | Get-Random }))
                $tld = $tlds | Get-Random
                $hostTarget = "www.$domain$tld"
            } else {
                # Generate IPv4 address
                $o1 = Get-Random -Minimum 1 -Maximum 224
                $o2 = Get-Random -Minimum 0 -Maximum 256
                $o3 = Get-Random -Minimum 0 -Maximum 256
                $o4 = Get-Random -Minimum 1 -Maximum 256
                $hostTarget = "$o1.$o2.$o3.$o4"
            }

            $urlBatch += "http://$hostTarget"
            $urlBatch += "https://$hostTarget"
        }

        # Process the batch concurrently
        $urlBatch[0..($MaxThreads-1)] | ForEach-Object -Parallel {
            try {
                # Strict timeout and Head method stops connection hanging
                $response = Invoke-WebRequest -Uri $_ -Method Head -TimeoutSec 1 -ErrorAction SilentlyContinue
                
                if ($response.StatusCode -eq 200) {
                    Write-Host "[FOUND] $_" -ForegroundColor Green
                    # Out-File handles system line breaks automatically
                    "$_" | Out-File -FilePath "live_results.txt" -Append -Encoding utf8
                }
            }
            catch {
                # Drop dead targets instantly
            }
        } -ThrottleLimit $MaxThreads
    }
}

# Run the infinite scanner
Start-InfiniteParallelScan -MaxThreads 30

# Force modern secure network transport protocols (TLS 1.2/1.3)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Absolute destination file paths
$masterPath = "$env:USERPROFILE\Desktop\MRT_Sorted_Database.txt"
$randomPath = "$env:USERPROFILE\Desktop\MRT_Random_Samples.txt"
$logPath    = "$env:USERPROFILE\Desktop\Extraction_Console_Log.txt"

Start-Transcript -Path $logPath -Force -Append

# ======================================================================
# 1. THE FLAWLESS PIPELINE WEB HARVESTER
# ======================================================================
$url = "https://support.microsoft.com/en-us/servicing/os/windows/2021/01/remove-specific-prevalent-malware-with-windows-malicious-software-removal-tool-kb890830"
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

Write-Host "Connecting directly to 2021 Support Article Web Structure..." -ForegroundColor Cyan
try {
    $web = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $userAgent -TimeoutSec 25
    $htmlContent = $web.Content
} catch {
    Write-Host "FATAL ERROR: Network packet drop." -ForegroundColor Red
    Stop-Transcript; return
}

Write-Host "Executing text extraction and architectural syntax filtering..." -ForegroundColor Cyan
# Reverted 100% to your original working broad text node harvester
$rawMatches = [regex]::Matches($htmlContent, '(?<=>)[A-Za-z0-9_\-\.\:\!\/ ]+(?=<)')
$purgedList = @()

foreach ($m in $rawMatches) {
    $item = $m.Value.Trim()
    
    # 1. Word Count Filter: Real malware names never contain spaces building standard sentences
    if (($item -split " ").Count -gt 3) {
        continue
    }
    
    # 2. Strict Standalone Menu Filter: Instantly drop corporate interface button leftovers
    if ($item -match "^\s*(Windows|Microsoft|System|Quiet mode|switches|detect-only|extended scan|Tool version|January|February|March|April|May|June|July|August|September|October|November|December|Janvier|Février|Mars|Avril|Mai|Juin|Juillet|Août|Septembre|Octobre|Novembre|Décembre|v\d\.\d+|Apply|Click|Select|Settings|Start|Switch|Purpose|Under|website|date and number|HoloLens|Company|Devices|Developer|Note|Yes|No)\s*$") {
        continue
    }
    
    # 3. Threat Engine Validation: Retain items matching standard platform classification properties
    if ($item.Length -gt 2 -and ($item -match ":|Win32|Win64|Worm|Trojan|Ransom|Spyware|Backdoor|Exploit|Tool|MacOS|Linux|Android|MSIL|Macro" -or $item -match "^[A-Z][a-zA-Z0-9\.]+$")) {
        if ($item -notmatch "<|>" -and $item -notmatch "http") {
            # Strip trailing execution release metadata dates and versions cleanly
            $cleanName = $item -replace "\s*(January|February|March|April|May|June|July|August|September|October|November|December|Janvier|Février|Mars|Avril|Mai|Juin|Juillet|Août|Septembre|Octobre|Novembre|Décembre)\s+\d{4}.*$", ""
            $cleanName = $cleanName -replace "\s*\(.*?\)\s*", ""
            $cleanName = $cleanName -replace "\s*v\.\s*\d.*", ""
            
            if ($cleanName.Trim() -ne "") {
                $purgedList += $cleanName.Trim()
            }
        }
    }
}

# Deduplicate clean items from the flawless working array safely
$cleanListOnly = @($purgedList | Select-Object -Unique | Where-Object { $_ -ne "" -and $_ -notmatch '^[0-9]+$' })
$totalCount = $cleanListOnly.Count

if ($totalCount -le 5) {
    Write-Host "FATAL ERROR: Isolated only $totalCount entries. Pipeline collection dropped items." -ForegroundColor Red
    Stop-Transcript; return
}

# ======================================================================
# 2. NEAT SEPARATION BY EXPLICIT ARCHITECTURAL PREFIXES (CASE-INSENSITIVE)
# ======================================================================
Write-Host "Sorting dynamic signatures strictly by architectural naming prefixes..." -ForegroundColor Yellow

$backdoors  = @($cleanListOnly | Where-Object { $_ -match "^Backdoor" } | Sort-Object)
$trojans    = @($cleanListOnly | Where-Object { $_ -match "^Trojan|^TrojanDownloader|^TrojanDropper" } | Sort-Object)
$worms      = @($cleanListOnly | Where-Object { $_ -match "^Worm" } | Sort-Object)
$viruses    = @($cleanListOnly | Where-Object { $_ -match "^Virus" } | Sort-Object)
$ransomware = @($cleanListOnly | Where-Object { $_ -match "^Ransom" } | Sort-Object)
$spyware    = @($cleanListOnly | Where-Object { $_ -match "^Spyware|^Adware" } | Sort-Object)
$tools      = @($cleanListOnly | Where-Object { $_ -match "^Exploit|^HackTool|^VirTool" } | Sort-Object)

# The generic bucket now flawlessly catches clean standalone legacy naming conventions (like Win32/WamarCrypt, Carberp, DarkGate)
$generic    = @($cleanListOnly | Where-Object { $_ -notmatch "^Backdoor|^Trojan|^Worm|^Virus|^Ransom|^Spyware|^Adware|^Exploit|^HackTool|^VirTool" } | Sort-Object)

# ======================================================================
# 3. CONCATENATE THE FILE LAYOUT SEQUENTIALLY
# ======================================================================
if (Test-Path $masterPath) { Remove-Item $masterPath -Force }

if ($backdoors.Count -gt 0)  { Add-Content -Path $masterPath -Value "---- 1. Backdoors ----"; $backdoors | Out-File $masterPath -Append -Encoding utf8 }
if ($trojans.Count -gt 0)    { Add-Content -Path $masterPath -Value "---- 2. Trojans ----"; $trojans | Out-File $masterPath -Append -Encoding utf8 }
if ($worms.Count -gt 0)      { Add-Content -Path $masterPath -Value "---- 3. Worms ----"; $worms | Out-File $masterPath -Append -Encoding utf8 }
if ($viruses.Count -gt 0)    { Add-Content -Path $masterPath -Value "---- 4. Viruses ----"; $viruses | Out-File $masterPath -Append -Encoding utf8 }
if ($ransomware.Count -gt 0) { Add-Content -Path $masterPath -Value "---- 5. Ransomware ----"; $ransomware | Out-File $masterPath -Append -Encoding utf8 }
if ($spyware.Count -gt 0)    { Add-Content -Path $masterPath -Value "---- 6. Spyware & Adware ----"; $spyware | Out-File $masterPath -Append -Encoding utf8 }
if ($tools.Count -gt 0)      { Add-Content -Path $masterPath -Value "---- 7. Exploits & HackTools ----"; $tools | Out-File $masterPath -Append -Encoding utf8 }
if ($generic.Count -gt 0)    { Add-Content -Path $masterPath -Value "---- 8. Generic Families (Unclassified, Misc) ----"; $generic | Out-File $masterPath -Append -Encoding utf8 }

# Fetch current system clock details for output display console trace
$currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Success! Master database organized by PREFIX sections: 'MRT_Sorted_Database.txt' ($totalCount entries)" -ForegroundColor Green
Write-Host "Execution Time: $currentDate" -ForegroundColor Green
Write-Host "------------------------------------------------------------------------" -Yellow

# ======================================================================
# 4. RANDOM SAMPLE SELECTION 
# ======================================================================
$inputCount = Read-Host "How many random entries would you like to extract into a separate file?"

if ($inputCount -as [int] -and [int]$inputCount -gt 0) {
    $countToPick = [int]$inputCount
    if ($countToPick -gt $totalCount) { $countToPick = $totalCount }
    
    $cleanListOnly | Get-Random -Count $countToPick | Out-File $randomPath -Encoding utf8
    Write-Host "Success! Grabbed $countToPick clean random samples to 'MRT_Random_Samples.txt' on your Desktop." -ForegroundColor Green
    
    # Automatically open both clean documents inside Notepad natively
    & notepad.exe $masterPath
    & notepad.exe $randomPath
} else {
    Write-Host "Error: Invalid number choice input." -ForegroundColor Red
}
Stop-Transcript

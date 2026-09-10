param(
    [string]$Mode = $null,
    [int]$Count = 0,
    [string]$TargetFolder = $null,
    [switch]$ShowMessage,
    [string]$TaskName = $null,
    [string]$GenerationMode = $null,
    [string]$RunTime = $null,
    [string]$TaskPriority = $null,
    [switch]$LegacyMode,
    [switch]$WindowMode,
    [switch]$PreferPS7,
    [switch]$PreferPS
)

$VersionMajor = 9
$VersionMinor = 9
$VersionPatch = 1
$VersionText = '{0}.{1}.{2} (Aug 5)' -f $VersionMajor, $VersionMinor, $VersionPatch
$LegacyVersionText = $VersionText + ' (Legacy Mode)'

$scriptPath = $MyInvocation.MyCommand.Path
# Error log location (same folder as the main log)
$errorLogPath = $null

# --- DEFINE Test-HasText BEFORE it's used ---

function Test-HasText {
    param($Value)
    if ($null -eq $Value) { return $false }
    $s = [string]$Value
    return ($s.Trim().Length -gt 0)
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-HasText $Path)) { return }
    if (Test-Path -LiteralPath $Path -PathType Container) { return }
    New-Item -ItemType Directory -LiteralPath $Path -Force | Out-Null
}

# --- NOW use Test-HasText safely ---

$script:IsAppDataCopy = $false
if (Test-HasText $scriptPath -and Test-HasText $env:APPDATA) {
    if ($scriptPath.ToLower().StartsWith($env:APPDATA.ToLower())) {
        $script:IsAppDataCopy = $true
    }
}

$script:UiResult = $false
$script:SelectedMode = $null
$script:SelectedCount = 0
$script:SelectedFolder = $null
$script:SelectedShowMessage = $false
$script:SelectedCreateShortcut = $false


$ApprovedVerbs = @(
    'Add','Approve','Assert','Backup','Block','Build','Cache','Capture','Check','Clear','Close','Click','Collapse','Commit','Compare','Complete','Compress','Confirm','Connect','Convert','Copy','Debug','Delete','Deploy','Detach','Deny','Disable','Disconnect','Dismount','Download','Edit','Enable','Encrypt','Enter','Exit','Expand','Export','Fetch','Find','Fix','Flush','Format','Get','Grant','Group','Hide','Import','Initialize','Install','Invoke','Join','Limit','Lock','Measure','Merge','Mount','Move','New','Open','Optimize','Out','Ping','Pop','Protect','Publish','Push','Read','Receive','Redo','Register','Remove','Rename','Repair','Request','Reset','Resolve','Restart','Resume','Revoke','Save','Scan','Search','Select','Send','Set','Show','Skip','Split','Start','Step','Stop','Submit','Switch','Sync','Test','Trace','Transform','Unblock','Undo','Uninstall','Unpublish','Unprotect','Unlock','Unregister','Update','Upload','Use','Verify','Wait','Watch','Write'
)

function Test-HasText { param($Value) if ($null -eq $Value) { return $false }; $s = [string]$Value; return ($s.Trim().Length -gt 0) }
function Ensure-Directory { param([string]$Path) if (-not (Test-HasText $Path)) { return }; if (Test-Path -LiteralPath $Path -PathType Container) { return }; New-Item -ItemType Directory -LiteralPath $Path -Force | Out-Null }

function Get-DesktopPath {
    $desktop = $null
    try { $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop) } catch {}
    if (Test-HasText $desktop) { return $desktop }

    try {
        $profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        if (Test-HasText $profile) {
            $desktop = Join-Path $profile 'Desktop'
            if (Test-Path -LiteralPath $desktop -PathType Container) { return $desktop }
        }
    } catch {}

    if (Test-HasText $env:USERPROFILE) {
        $desktop = Join-Path $env:USERPROFILE 'Desktop'
        if (Test-Path -LiteralPath $desktop -PathType Container) { return $desktop }
    }

    # Fallback: use a known-good folder instead of $null
    return $env:TEMP
}

function Get-DriveRootFromPath {
    param([string]$Path)
    if (-not (Test-HasText $Path)) { return $null }
    try {
        $resolved = $Path
        if (-not [System.IO.Path]::IsPathRooted($resolved)) {
            $rp = Resolve-Path -LiteralPath $resolved -ErrorAction Stop
            if (-not $rp) { return $null }
            $resolved = $rp.Path
        }
        $root = [System.IO.Path]::GetPathRoot($resolved)
        if (Test-HasText $root) { return $root }
    } catch {}
    return $null
}

function Get-FreeSpaceOnDrive {
    param([string]$Path)
    try {
        $root = Get-DriveRootFromPath $Path
        if (-not (Test-HasText $root)) { return 0 }
        $drive = New-Object System.IO.DriveInfo($root)
        if ($drive -and $drive.IsReady) { return [int64]$drive.AvailableFreeSpace }
    } catch {}
    return 0
}

function Write-LogLine { param([string]$LogPath, [string]$Message) Add-Content -LiteralPath $LogPath -Value $Message }
function Write-Both {
    param([string]$LogPath,[string]$Message,[ConsoleColor]$Foreground = [ConsoleColor]::Gray,[ConsoleColor]$Background = [ConsoleColor]::Black)
    Write-Host $Message -ForegroundColor $Foreground -BackgroundColor $Background
    Write-LogLine $LogPath $Message
}
function Write-Status { param([string]$Message,[ConsoleColor]$Foreground = [ConsoleColor]::Gray,[ConsoleColor]$Background = [ConsoleColor]::Black) Write-Host $Message -ForegroundColor $Foreground -BackgroundColor $Background }

function Load-UiAssemblies {
    try { Add-Type -AssemblyName System.Windows.Forms | Out-Null } catch { [Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null }
    try { Add-Type -AssemblyName System.Drawing | Out-Null } catch { [Reflection.Assembly]::LoadWithPartialName('System.Drawing') | Out-Null }
}

if (-not ('Win32.NativeMethods' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace Win32 {
    public static class NativeMethods {
        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
}
"@
}

function Show-ConsoleWindow {
    try {
        $h = [Win32.NativeMethods]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][Win32.NativeMethods]::ShowWindow($h, 5) }
    } catch {}
}

function Hide-ConsoleWindow {
    try {
        $h = [Win32.NativeMethods]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][Win32.NativeMethods]::ShowWindow($h, 0) }
    } catch {}
}

function Copy-SelfToAppData {
    if (-not (Test-HasText $scriptPath)) { return $null }
    if (-not (Test-HasText $env:APPDATA)) { return $null }
    try { $dest = Join-Path $env:APPDATA 'FileGenerator.ps1'; Copy-Item -LiteralPath $scriptPath -Destination $dest -Force; return $dest } catch { return $null }
}

function Get-IconCountFromFile {
    param([string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        return 0
    }

    # Define ExtractIconEx via Add-Type (PS 2.0 style)
    if (-not ('Win32.IconMethods' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace Win32 {
    public static class IconMethods {
        [DllImport("shell32.dll", CharSet = CharSet.Auto)]
        public static extern uint ExtractIconEx(
            string lpszFile,
            int nIconIndex,
            IntPtr[] phiconLarge,
            IntPtr[] phiconSmall,
            uint nIcons
        );
    }
}
"@
    }

    # Pass nIconIndex = -1, both arrays = NULL, nIcons = 0 → returns total icon count
    $count = [Win32.IconMethods]::ExtractIconEx($FilePath, -1, $null, $null, 0)
    return [int]$count
}

function Get-RandomShell32IconLocation {
    $shell32 = Join-Path $env:SystemRoot 'System32\shell32.dll'
    if (-not (Test-Path -LiteralPath $shell32)) { return 'shell32.dll,0' }
    $rnd = New-Object System.Random
    return ($shell32 + ',' + $rnd.Next(0, 300))
}

function New-DesktopShortcut {
    param(
        [string]$ShortcutName,
        [string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$IconLocation = ''
    )
    $desktop = Get-DesktopPath
    if (-not (Test-HasText $desktop)) { return $null }
    Ensure-Directory $desktop
    $linkPath = Join-Path $desktop ($ShortcutName + '.lnk')
    if (-not (Test-HasText $linkPath)) { return $null }
    if (-not (Test-HasText $TargetPath)) { return $null }
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($linkPath)
        $shortcut.TargetPath = $TargetPath
        if (Test-HasText $Arguments) { $shortcut.Arguments = $Arguments }
        if (Test-HasText $WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
        if (Test-HasText $IconLocation) { $shortcut.IconLocation = $IconLocation }
        $shortcut.Save()
        if (Test-Path -LiteralPath $linkPath) { return $linkPath }
    } catch {}
    return $null
}

function Get-PowerShellExePath {
    param(
        [switch]$PreferPS7,
        [switch]$PreferPS
    )

    $ps7Path = $null
    $ps5Path = $null

    # Try to find pwsh.exe (PowerShell 7+) via PATH
    try {
        $p = (Get-Command pwsh.exe -ErrorAction Stop | Select-Object -First 1).Path
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            $ps7Path = $p
        }
    } catch {}

    # Try to find powershell.exe (Windows PowerShell) via PATH
    try {
        $p = (Get-Command powershell.exe -ErrorAction Stop | Select-Object -First 1).Path
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            $ps5Path = $p
        }
    } catch {}

    # Fallback: explicit System32 Windows PowerShell path
    if (-not $ps5Path) {
        $p = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $ps5Path = $p
        }
    }

    # If user explicitly wants PS 7
    if ($PreferPS7) {
        if ($ps7Path) { return $ps7Path }
        if ($ps5Path) { return $ps5Path }
        return $null
    }

    # If user explicitly wants Windows PowerShell
    if ($PreferPS) {
        if ($ps5Path) { return $ps5Path }
        if ($ps7Path) { return $ps7Path }
        return $null
    }

    # Default: prefer System32 PS 5.1
    if ($ps5Path) { return $ps5Path }
    if ($ps7Path) { return $ps7Path }

    return $null
}

function Get-SystemQuery { param([string]$ClassName,[string]$Filter = $null) try { if ($Filter) { return Get-WmiObject -Class $ClassName -Filter $Filter -ErrorAction Stop } return Get-WmiObject -Class $ClassName -ErrorAction Stop } catch {} try { if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { if ($Filter) { return Get-CimInstance -ClassName $ClassName -Filter $Filter -ErrorAction Stop } return Get-CimInstance -ClassName $ClassName -ErrorAction Stop } } catch {} return $null }

function Clean-Text { param($Value) if ($null -eq $Value) { return $null }; $s = ([string]$Value).Trim(); if (-not (Test-HasText $s)) { return $null }; if ($s.StartsWith('@')) { $s = $s.Substring(1); $comma = $s.IndexOf(','); if ($comma -gt 0) { $s = $s.Substring(0, $comma) } }; return (($s -replace '®','(R)') -replace '©','(C)' -replace '™','(TM)') -replace '\s+',' ' }
function Is-BadDisplayText { param($Value) if ($null -eq $Value) { return $true }; $s = ([string]$Value).Trim(); if (-not (Test-HasText $s)) { return $true }; return ($s -eq '%1' -or $s -match '^[%@]' -or $s -match '\\' -or $s -match '^[A-Za-z]:' -or $s -match '\.dll\b|\.exe\b|\.mui\b|\.res\b') }
function Resolve-FriendlyText { param($Value) $s = Clean-Text $Value; if (Test-HasText $s) { return $s }; return $null }

function Get-ExePathFromCommand {
    param($Command)
    if ($null -eq $Command) { return $null }
    $cmd = ([string]$Command).Trim()
    if (-not (Test-HasText $cmd)) { return $null }
    if ($cmd.StartsWith('"')) { $end = $cmd.IndexOf('"', 1); if ($end -gt 1) { return $cmd.Substring(1, $end - 1) } }
    if ($cmd -match '^(.*?\.(?:exe|com|bat|cmd))\s') { return $matches[1] }
    $space = $cmd.IndexOf(' ')
    if ($space -gt 0) { return $cmd.Substring(0, $space) }
    return $cmd
}

function Get-FriendlyAppName {
    param($Command)
    $exe = Get-ExePathFromCommand $Command
    if (-not (Test-HasText $exe) -or -not (Test-Path -LiteralPath $exe)) { return $null }
    try {
        $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
        foreach ($candidate in @($v.FileDescription, $v.ProductName, [System.IO.Path]::GetFileNameWithoutExtension($exe))) {
            $n = Resolve-FriendlyText $candidate
            if ($n -and -not (Is-BadDisplayText $n)) { return $n }
        }
    } catch {}
    return $null
}

function Get-FileTypeName {
    param($ClassKey, $ProgId, $Ext)
    $candidates = @()
    try {
        if ($ClassKey) {
            $friendly = $ClassKey.GetValue('FriendlyTypeName'); if ($friendly) { $candidates += (Resolve-FriendlyText $friendly) }
            $def = $ClassKey.GetValue(''); if ($def) { $candidates += (Resolve-FriendlyText $def) }
        }
    } catch {}
    if ($ProgId) { $candidates += (Resolve-FriendlyText $ProgId) }
    foreach ($n in $candidates) { if ($n -and -not (Is-BadDisplayText $n)) { return $n } }
    return $Ext
}

function Get-AssociationInfo {
    param($Ext)
    $info = New-Object PSObject -Property @{ Ext = $Ext; ProgId = $null; FileType = $Ext; OpenWith = $null; Command = $null; Valid = $false }
    try {
        $extPath = 'Registry::HKEY_CLASSES_ROOT\' + $Ext
        if (-not (Test-Path -LiteralPath $extPath)) { return $info }
        $extKey = Get-Item $extPath
        $progId = $extKey.GetValue('')
        if (-not $progId) { return $info }
        $info.ProgId = $progId
        $classPath = 'Registry::HKEY_CLASSES_ROOT\' + $progId
        if (-not (Test-Path -LiteralPath $classPath)) { return $info }
        $classKey = Get-Item $classPath
        $info.FileType = Get-FileTypeName $classKey $progId $Ext
        $shellOpen = $classPath + '\shell\open\command'
        if (Test-Path -LiteralPath $shellOpen) {
            $cmd = (Get-Item $shellOpen).GetValue('')
            if ($cmd) { $info.Command = $cmd; $info.OpenWith = Get-FriendlyAppName $cmd; if ($info.OpenWith) { $info.Valid = $true } }
        }
    } catch { $info.Valid = $false }
    if (-not $info.OpenWith) { $info.OpenWith = $info.FileType }
    return $info
}

function Get-AssociationCache {
    $cache = @()
    Get-ChildItem -Path 'Registry::HKEY_CLASSES_ROOT' | ForEach-Object {
        if ($_.PSChildName -match '^\.' -and $_.PSChildName -notmatch '\s') {
            $info = Get-AssociationInfo $_.PSChildName
            if ($info.Valid) { $cache += $info }
        }
    }
    return $cache
}

function Get-PairBaseClassic { [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName()) }
function Get-PairBasePlus { param($Verbs, $Rnd) $n = $Verbs.Count; if ($n -lt 2) { return $null }; for ($attempt=0; $attempt -lt 400; $attempt++) { $w1 = $Verbs[$Rnd.Next(0,$n)]; $w2 = $Verbs[$Rnd.Next(0,$n)]; if ($w1 -ne $w2) { return ($w1 + $w2) } } return $null }

function Get-FileHeaderBytes {
    param($Ext)
    switch ($Ext.ToLower()) {
        '.jpg'  { [byte[]](0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01) }
        '.jpeg' { [byte[]](0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01) }
        '.png'  { [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A) }
        '.mp3'  { [byte[]](0x49,0x44,0x33,0x03,0x00,0x00,0x00,0x00,0x00,0x21) }
        '.mp4'  { [byte[]](0x00,0x00,0x00,0x18,0x66,0x74,0x79,0x70,0x69,0x73,0x6F,0x6D,0x00,0x00,0x02,0x00,0x69,0x73,0x6F,0x6D,0x69,0x73,0x6F,0x32) }
        '.docx' { [byte[]](0x50,0x4B,0x03,0x04) }
        '.exe'  { [byte[]](0x4D,0x5A) }
        '.html' { [byte[]](0x3C,0x21,0x44,0x4F,0x54,0x59,0x50,0x45,0x20,0x68,0x74,0x6D,0x6C) }
        '.htm'  { [byte[]](0x3C,0x21,0x44,0x4F,0x54,0x59,0x50,0x45,0x20,0x68,0x74,0x6D,0x6C) }
        '.xml'  { [byte[]](0x3C,0x3F,0x78,0x6D,0x6C,0x20,0x76,0x65,0x72,0x73,0x69,0x6F,0x6E,0x3D,0x22,0x31,0x2E,0x30,0x22,0x20,0x65,0x6E,0x63,0x6F,0x64,0x69,0x6E,0x67,0x3D,0x22,0x75,0x74,0x66,0x2D,0x38,0x22,0x3F,0x3E) }
        default { $null }
    }
}

function Get-RandomFileSize { param($Rnd) $Rnd.Next(10KB, 100MB + 1) }
function Write-TestFile { param($FinalPath, $Header, $Rnd) $size = Get-RandomFileSize $Rnd; $fs = $null; try { $fs = New-Object System.IO.FileStream($FinalPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None); if ($Header) { $headerLen = $Header.Length; if ($size -lt $headerLen) { $size = $headerLen }; $fs.Write($Header, 0, $headerLen); $remaining = $size - $headerLen; if ($remaining -gt 0) { $bufferSize = 64KB; if ($remaining -lt $bufferSize) { $bufferSize = $remaining }; $buffer = New-Object byte[] $bufferSize; while ($remaining -gt 0) { $chunkSize = $bufferSize; if ($remaining -lt $chunkSize) { $chunkSize = $remaining }; if ($chunkSize -ne $buffer.Length) { $buffer = New-Object byte[] $chunkSize }; $Rnd.NextBytes($buffer); $fs.Write($buffer, 0, $chunkSize); $remaining -= $chunkSize } } } else { $bufferSize = 64KB; if ($size -lt $bufferSize) { $bufferSize = $size }; $buffer = New-Object byte[] $bufferSize; $remaining = $size; while ($remaining -gt 0) { $chunkSize = $bufferSize; if ($remaining -lt $chunkSize) { $chunkSize = $remaining }; if ($chunkSize -ne $buffer.Length) { $buffer = New-Object byte[] $chunkSize }; $Rnd.NextBytes($buffer); $fs.Write($buffer, 0, $chunkSize); $remaining -= $chunkSize } } } finally { if ($fs) { $fs.Close(); $fs.Dispose() } } }

function Format-Bytes { param([double]$Bytes) if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) } if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) } if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) } if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) } return ('{0} B' -f [int64]$Bytes) }

function Test-IsVM { $cs = Get-SystemQuery -ClassName Win32_ComputerSystem; $combo = ''; if ($cs) { $combo = ('' + $cs.Manufacturer + ' ' + $cs.Model).ToLower() }; return ($combo -match 'virtual|vmware|vbox|virtualbox|hyper-v|microsoft corporation|kvm|xen|qemu|parallels|bhyve') }
function Test-RemoteDisplayClue { try { return ([string]$env:SESSIONNAME -match 'RDP|ICA|VNC') } catch { return $false } }
function Copy-SelfToAppData { if (-not (Test-HasText $scriptPath)) { return $null }; if (-not (Test-HasText $env:APPDATA)) { return $null }; try { $dest = Join-Path $env:APPDATA 'FileGenerator.ps1'; Copy-Item -LiteralPath $scriptPath -Destination $dest -Force; return $dest } catch { return $null } }

function Write-SessionHeader {
    param($LogPath, [string]$ModeLabel)
    $cs = Get-SystemQuery -ClassName Win32_ComputerSystem; $os = Get-SystemQuery -ClassName Win32_OperatingSystem; $cpu = Get-SystemQuery -ClassName Win32_Processor | Select-Object -First 1
    $psVersion = $PSVersionTable.PSVersion; $dotNetVersion = [System.Environment]::Version; $cwd = (Get-Location).Path
    $freeSpaceGB = [Math]::Round((Get-FreeSpaceOnDrive $cwd) / 1GB, 2)
    Write-Both $LogPath '--- Session Start ---' Cyan
    Write-Both $LogPath ('Mode: ' + $ModeLabel) Yellow
    Write-Both $LogPath ('Manufacturer: ' + $(if($cs){$cs.Manufacturer}else{'Unknown'})) Yellow
    Write-Both $LogPath ('Model: ' + $(if($cs){$cs.Model}else{'Unknown'})) Yellow
    Write-Both $LogPath ('CPU: ' + $(if($cpu){$cpu.Name}else{'Unknown'})) Yellow
    Write-Both $LogPath ('OS: ' + $(if($os){$os.Caption}else{'Unknown'})) Yellow
    Write-Both $LogPath ('PowerShell: ' + $psVersion.ToString()) Yellow
    Write-Both $LogPath ('.NET: ' + $dotNetVersion.ToString()) Yellow
    Write-Both $LogPath ('Free space: ' + $freeSpaceGB + ' GB') Yellow
    Write-Both $LogPath ('Working folder: ' + $cwd) Yellow
    Write-Both $LogPath ('Version: ' + $VersionText) Yellow
}

function Write-ErrorLog {
    param([string]$Message)
    if (-not (Test-HasText $errorLogPath)) { return }
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "$timestamp $Message"
        Add-Content -LiteralPath $errorLogPath -Value $line -ErrorAction SilentlyContinue
    } catch {
        # Best effort; ignore if we can't write the error log
    }
}

function Write-CurrentErrorsToLog {
    if (-not (Test-HasText $errorLogPath)) { return }
    if ($Error.Count -eq 0) { return }

    Write-ErrorLog "Captured error stream at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'):"
    foreach ($err in $Error) {
        try {
            $text = $err | Out-String
            # Remove extra newlines for compactness
            $text = $text -replace "`r`n", " " -replace "`n", " "
            Write-ErrorLog "  - $text"
        } catch {
            Write-ErrorLog "  - (failed to format error object)"
        }
    }
}

function Show-InfoMode {
    $targetFolder = if (Test-HasText $TargetFolder) { $TargetFolder } else { (Get-Location).Path }
    $freeSpaceGB = [Math]::Round((Get-FreeSpaceOnDrive $targetFolder) / 1GB, 2)
    Write-Status '--- PC Information ---' Cyan
    Write-Status ('Free space: ' + $freeSpaceGB + ' GB') Yellow
    Write-Status ('Target folder: ' + $targetFolder) Yellow
}
function Show-AboutMode { param([switch]$Legacy) Write-Status '--- About ---' Cyan; Write-Status 'File Generator' Yellow; if ($Legacy) { Write-Status ('Version: ' + $LegacyVersionText) Green } else { Write-Status ('Version: ' + $VersionText) Green } }

function Get-ReadableRatio { param([double]$Bytes,[double]$UnitBytes) if ($UnitBytes -le 0) { return '0.00x' }; return ('{0:N2}x' -f ($Bytes / $UnitBytes)) }
function Get-MediaEquivalentText { param([int64]$TotalBytes) @(('650MB CDs: ' + (Get-ReadableRatio $TotalBytes 650MB)),('700MB CDs: ' + (Get-ReadableRatio $TotalBytes 700MB)),('1.44MB floppies: ' + (Get-ReadableRatio $TotalBytes 1.44MB)),('2.88MB floppies: ' + (Get-ReadableRatio $TotalBytes 2.88MB)),('25GB Blu-ray: ' + (Get-ReadableRatio $TotalBytes 25GB)),('50GB Blu-ray: ' + (Get-ReadableRatio $TotalBytes 50GB)),('15GB HD DVD: ' + (Get-ReadableRatio $TotalBytes 15GB)),('30GB HD DVD: ' + (Get-ReadableRatio $TotalBytes 30GB))) }
function Get-EstimatedFilesToFillDrive { param([int64]$AverageFileSizeBytes,[double]$FreeSpaceBytes) if ($AverageFileSizeBytes -le 0) { return 0 }; return [Math]::Ceiling($FreeSpaceBytes / $AverageFileSizeBytes) }

function Invoke-Generation {
    param($Modes,[int]$Count,$AssocCache,$VerbList,$Rnd,$Cwd,$LogPath,[int]$PlusCeiling)
    $generatedFiles = @()
    if ($Modes.Count -eq 1 -and $Modes[0] -eq 'plus' -and $Count -gt $PlusCeiling) { $Count = $PlusCeiling }
    for ($i = 1; $i -le $Count; $i++) {
        $mode = $Modes[$Rnd.Next(0, $Modes.Count)]
        $pick = $AssocCache[$Rnd.Next(0, $AssocCache.Count)]
        if (-not $pick) { continue }
        $base = if ($mode -eq 'plus') { Get-PairBasePlus $VerbList $Rnd } else { Get-PairBaseClassic }
        if (-not (Test-HasText $base)) { continue }
        $finalPath = Join-Path $Cwd ($base + $pick.Ext)
        Write-TestFile $finalPath (Get-FileHeaderBytes $pick.Ext) $Rnd
        $sizeBytes = (Get-Item -LiteralPath $finalPath).Length
        $sizeText = Format-Bytes $sizeBytes

        # PS 2.0–compatible object creation
        $fileObj = New-Object PSObject
        $fileObj | Add-Member -Name Path -Value $finalPath -MemberType NoteProperty
        $fileObj | Add-Member -Name Size -Value ([int64]$sizeBytes) -MemberType NoteProperty
        $generatedFiles += $fileObj

        Write-Both $LogPath '--- File Details ---' Cyan
        Write-Both $LogPath ('Mode: ' + $mode) Green
        Write-Both $LogPath ('File Type: ' + $pick.FileType) Yellow
        Write-Both $LogPath ('Open With: ' + $pick.OpenWith) Green
        Write-Both $LogPath ('File: ' + $finalPath) Yellow
        Write-Both $LogPath ('Size: ' + $sizeText + ' (' + $sizeBytes + ' bytes)') Yellow
        Write-Both $LogPath ('Files generated so far: ' + $generatedFiles.Count) Cyan
    }
    if ($generatedFiles.Count -gt 0) {
        $stats = $generatedFiles | Measure-Object -Property Size -Sum -Average -Minimum -Maximum
        $totalSize = [int64]$stats.Sum
        $fileCount = [int]$stats.Count
        $avgSize = if ($stats.Average) { [int64]$stats.Average } else { 0 }
        $minSize = if ($stats.Minimum) { [int64]$stats.Minimum } else { 0 }
        $maxSize = if ($stats.Maximum) { [int64]$stats.Maximum } else { 0 }
        Write-Both $LogPath '--- Generation Statistics ---' Cyan
        Write-Both $LogPath ('Files generated: ' + $fileCount) Yellow
        Write-Both $LogPath ('Total size: ' + (Format-Bytes $totalSize) + ' (' + $totalSize + ' bytes)') Yellow
        Write-Both $LogPath ('Average size: ' + (Format-Bytes $avgSize) + ' (' + $avgSize + ' bytes)') Green
        Write-Both $LogPath ('Smallest file: ' + (Format-Bytes $minSize) + ' (' + $minSize + ' bytes)') Green
        Write-Both $LogPath ('Largest file: ' + (Format-Bytes $maxSize) + ' (' + $maxSize + ' bytes)') Green
    }
}

function Invoke-DebugGeneration {
    param($AssocCache, $Rnd, $Cwd, $LogPath)
    $generatedFiles = @()
    foreach ($ext in @('.jpg','.jpeg','.png','.mp3','.mp4','.docx','.exe','.html','.htm','.xml')) {
        $pick = $AssocCache | Where-Object { $_.Ext -eq $ext } | Select-Object -First 1
        if (-not $pick) { continue }
        $base = Get-PairBaseClassic
        $finalPath = Join-Path $Cwd ($base + $ext)
        Write-TestFile $finalPath (Get-FileHeaderBytes $ext) $Rnd
        $sizeBytes = (Get-Item -LiteralPath $finalPath).Length
        $sizeText = Format-Bytes $sizeBytes

        # PS 2.0–compatible object creation
        $fileObj = New-Object PSObject
        $fileObj | Add-Member -Name Path -Value $finalPath -MemberType NoteProperty
        $fileObj | Add-Member -Name Size -Value ([int64]$sizeBytes) -MemberType NoteProperty
        $generatedFiles += $fileObj

        Write-Both $LogPath '--- File Details ---' Cyan
        Write-Both $LogPath 'Mode: debug' Green
        Write-Both $LogPath ('File Type: ' + $pick.FileType) Yellow
        Write-Both $LogPath ('Open With: ' + $pick.OpenWith) Green
        Write-Both $LogPath ('File: ' + $finalPath) Yellow
        Write-Both $LogPath ('Size: ' + $sizeText + ' (' + $sizeBytes + ' bytes)') Yellow
    }
    if ($generatedFiles.Count -gt 0) {
        $stats = $generatedFiles | Measure-Object -Property Size -Sum -Average -Minimum -Maximum
        $totalSize = [int64]$stats.Sum
        $fileCount = [int]$stats.Count
        $avgSize = if ($stats.Average) { [int64]$stats.Average } else { 0 }
        $minSize = if ($stats.Minimum) { [int64]$stats.Minimum } else { 0 }
        $maxSize = if ($stats.Maximum) { [int64]$stats.Maximum } else { 0 }
        Write-Both $LogPath '--- Generation Statistics ---' Cyan
        Write-Both $LogPath ('Files generated: ' + $fileCount) Yellow
        Write-Both $LogPath ('Total size: ' + (Format-Bytes $totalSize) + ' (' + $totalSize + ' bytes)') Yellow
        Write-Both $LogPath ('Average size: ' + (Format-Bytes $avgSize) + ' (' + $avgSize + ' bytes)') Green
        Write-Both $LogPath ('Smallest file: ' + (Format-Bytes $minSize) + ' (' + $minSize + ' bytes)') Green
        Write-Both $LogPath ('Largest file: ' + (Format-Bytes $maxSize) + ' (' + $maxSize + ' bytes)') Green
    }
}

function Invoke-ScheduledTaskMode { Write-Status 'Scheduled task mode is unchanged.' Yellow }

function Invoke-SelfShortcutMode {
    # AppData copy must not create shortcuts
    if ($script:IsAppDataCopy) {
        return $null
    }

    # Ensure we can show a message box
    try { Add-Type -AssemblyName System.Windows.Forms | Out-Null } catch { [Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null }

    # 1. Resolve script path (already resolved at top of script)
    if (-not (Test-HasText $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "ERROR: Cannot determine script path.",
            "File Generator - Shortcut Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $null
    }

    # 2. Copy to APPDATA (like your original logic)
    $copiedScript = $scriptPath
    if (Test-HasText $env:APPDATA) {
        try {
            $dest = Join-Path $env:APPDATA 'FileGenerator.ps1'
            Ensure-Directory (Split-Path $dest)
            Copy-Item -LiteralPath $scriptPath -Destination $dest -Force
            $copiedScript = $dest
        } catch {
            # Ignore copy errors, keep using original path
        }
    }

    # 3. PowerShell executable (respect -PreferPS7 / -PreferPS, default = PS 5.1)
$psExe = Get-PowerShellExePath -PreferPS7:$PreferPS7 -PreferPS:$PreferPS
if (-not $psExe) {
    [System.Windows.Forms.MessageBox]::Show(
        "ERROR: Could not locate PowerShell executable.",
        "File Generator - Shortcut Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return $null
}

    # 4. Arguments
    $argsString = '-NoProfile -ExecutionPolicy Bypass -File "' + $copiedScript + '" -WindowMode'

    # 5. Desktop path
    $desktop = Get-DesktopPath
    if (-not (Test-HasText $desktop)) {
        [System.Windows.Forms.MessageBox]::Show(
            "ERROR: Could not resolve Desktop path.",
            "File Generator - Shortcut Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $null
    }

    Ensure-Directory $desktop

    # 6. Shortcut path
    $shortcutName = 'File Generator'
    $linkPath = Join-Path $desktop ($shortcutName + '.lnk')

    # 7. Create shortcut using WScript.Shell
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($linkPath)

        $shortcut.TargetPath = $psExe
        $shortcut.Arguments = $argsString
        $shortcut.WorkingDirectory = Split-Path $copiedScript

        # Choose randomly between shell32.dll and imageres.dll
        # Choose randomly between shell32.dll and imageres.dll
$shell32Path = Join-Path $env:SystemRoot 'System32\shell32.dll'
$imageresPath = Join-Path $env:SystemRoot 'System32\imageres.dll'

# Get actual icon counts
$shell32Count = Get-IconCountFromFile $shell32Path
$imageresCount  = Get-IconCountFromFile $imageresPath

# Fallbacks if detection fails
if ($shell32Count -le 0) { $shell32Count = 100 }
if ($imageresCount -le 0) { $imageresCount = 100 }

$rnd = New-Object System.Random
$useImageRes = ($rnd.Next(0, 2) -eq 1)  # 50% chance

if ($useImageRes) {
    $iconDllPath = $imageresPath
    # Random index in [0, imageresCount)
    $iconIndex = $rnd.Next(0, $imageresCount)
} else {
    $iconDllPath = $shell32Path
    # Random index in [0, shell32Count)
    $iconIndex = $rnd.Next(0, $shell32Count)
}

$shortcut.IconLocation = "$iconDllPath,$iconIndex"

        $shortcut.IconLocation = "$iconDllPath,$iconIndex"
        $shortcut.Description = 'File Generator (PowerShell)'
        $shortcut.Save()

        if (Test-Path -LiteralPath $linkPath) {
            $dllName = if ($useImageRes) { 'imageres.dll' } else { 'shell32.dll' }
            [System.Windows.Forms.MessageBox]::Show(
                "Shortcut created:`r`n$linkPath`r`nIcon: $dllName,$iconIndex",
                "File Generator - Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return $linkPath
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Shortcut file not found after Save().`r`nPath: $linkPath",
                "File Generator - Shortcut Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return $null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "ERROR creating shortcut:`r`n$_",
            "File Generator - Shortcut Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $null
    }
}

function Invoke-WindowMode {
    Load-UiAssemblies
    [System.Windows.Forms.Application]::EnableVisualStyles()
    Show-ConsoleWindow
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'File Generator'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(460,320)
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $lblMode = New-Object System.Windows.Forms.Label; $lblMode.Text='Mode:'; $lblMode.Location=New-Object System.Drawing.Point(20,20); $lblMode.AutoSize=$true
    $cmbMode = New-Object System.Windows.Forms.ComboBox; $cmbMode.Location=New-Object System.Drawing.Point(140,16); $cmbMode.Width=220; [void]$cmbMode.Items.AddRange(@('classic','plus','both','debug')); $cmbMode.SelectedIndex=0
    $lblCount = New-Object System.Windows.Forms.Label; $lblCount.Text='Count:'; $lblCount.Location=New-Object System.Drawing.Point(20,60); $lblCount.AutoSize=$true
    $txtCount = New-Object System.Windows.Forms.TextBox; $txtCount.Location=New-Object System.Drawing.Point(140,56); $txtCount.Width=100; $txtCount.Text='1'
    $lblFolder = New-Object System.Windows.Forms.Label; $lblFolder.Text='Folder:'; $lblFolder.Location=New-Object System.Drawing.Point(20,100); $lblFolder.AutoSize=$true
    $txtFolder = New-Object System.Windows.Forms.TextBox; $txtFolder.Location=New-Object System.Drawing.Point(140,96); $txtFolder.Width=260; $txtFolder.Text=(Get-Location).Path
    $chkMsg = New-Object System.Windows.Forms.CheckBox; $chkMsg.Text='Show completion message'; $chkMsg.Location=New-Object System.Drawing.Point(140,136); $chkMsg.AutoSize=$true
    $chkShortcut = New-Object System.Windows.Forms.CheckBox; $chkShortcut.Text='Create desktop shortcut'; $chkShortcut.Location=New-Object System.Drawing.Point(140,166); $chkShortcut.AutoSize=$true
    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text='Run'; $btnOk.Location=New-Object System.Drawing.Point(140,210); $btnOk.DialogResult=[System.Windows.Forms.DialogResult]::OK
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text='Cancel'; $btnCancel.Location=New-Object System.Drawing.Point(230,210); $btnCancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
    $form.AcceptButton = $btnOk; $form.CancelButton = $btnCancel
    $form.Controls.AddRange(@($lblMode,$cmbMode,$lblCount,$txtCount,$lblFolder,$txtFolder,$chkMsg,$chkShortcut,$btnOk,$btnCancel))
    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { $form.Dispose(); return }
    $script:SelectedMode = [string]$cmbMode.SelectedItem
    try { $script:SelectedCount = [int]$txtCount.Text } catch { $script:SelectedCount = 1 }
    if ($script:SelectedCount -lt 1) { $script:SelectedCount = 1 }
    $script:SelectedFolder = if (Test-HasText $txtFolder.Text) { $txtFolder.Text } else { (Get-Location).Path }
    $script:SelectedShowMessage = [bool]$chkMsg.Checked
    $script:SelectedCreateShortcut = [bool]$chkShortcut.Checked
    $script:UiResult = $true
    $form.Dispose()
}

$useWindow = $false

if ($script:IsAppDataCopy) {
    # AppData copy: never use GUI
    $useWindow = $false
} else {
    if ($WindowMode) { $useWindow = $true }
    if (-not $Mode -and -not $LegacyMode -and $Host.Name -eq 'ConsoleHost') { $useWindow = $true }
}

$assocCache = Get-AssociationCache
if ($assocCache.Count -eq 0) { Write-Status 'No valid associations found.' Red; exit }
$rnd = New-Object System.Random
$cwd = $null

if (Test-HasText $TargetFolder) {
    $cwd = $TargetFolder
} else {
    try { $cwd = (Get-Location).Path } catch {}
}

if (-not (Test-HasText $cwd)) {
    try { $cwd = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) } catch {}
}

if (-not (Test-HasText $cwd)) {
    $cwd = $env:TEMP
}

Ensure-Directory $cwd
$logPath = Join-Path $cwd 'generation-log.txt'
$errorLogPath = Join-Path $cwd 'errors-log.txt'
$plusCeiling = $ApprovedVerbs.Count * ($ApprovedVerbs.Count - 1)
$sessionStarted = $false
# Global error trap – writes raw PowerShell errors to errors-log.txt
trap {
    Write-ErrorLog "Unhandled error: $_"
    Write-CurrentErrorsToLog
    # Continue so the script can still exit or fall back to menu
}

if ($useWindow) {
    Invoke-SelfShortcutMode
    Invoke-WindowMode
    if (-not $script:UiResult) { exit }
    $Mode = $script:SelectedMode
    $Count = $script:SelectedCount
    $TargetFolder = $script:SelectedFolder
    $ShowMessage = $script:SelectedShowMessage
}

if ($LegacyMode) {
    if (-not $sessionStarted) { Write-SessionHeader $logPath 'Legacy'; $sessionStarted = $true }
    while ($true) {
        try {
        Write-Host 'Legacy mode:'
        Write-Host '1 = Classic'
        Write-Host '2 = Plus'
        Write-Host '3 = Exit'
        Write-Host '4 = Both'
        Write-Host '5 = Debug'
        Write-Host '6 = Info'
        Write-Host '7 = Schedule Task'
        Write-Host '8 = About'
        Write-Host '9 = Create Shortcut'
        Write-Host '0 = Return to Window Mode'
        $choice = Read-Host 'Enter key'
        if ($choice -eq '3') { break }
        if ($choice -eq '6') { Show-InfoMode; continue }
        if ($choice -eq '7') { Invoke-ScheduledTaskMode; continue }
        if ($choice -eq '8') { Show-AboutMode -Legacy; continue }
        if ($choice -eq '9') { Invoke-SelfShortcutMode; continue }
        if ($choice -eq '0') { Invoke-WindowMode; exit }
        if ($choice -eq '5') { Invoke-DebugGeneration $assocCache $rnd $cwd $logPath; continue }
        if ($choice -eq '4') { $modeList = @('classic','plus') }
        elseif ($choice -eq '2') { $modeList = @('plus') }
        elseif ($choice -eq '1') { $modeList = @('classic') }
        else { Write-Status 'Invalid choice.' Red; continue }
        $quantityText = Read-Host 'How many files to generate?'
        $requested = 0
        try { $requested = [int]$quantityText } catch { $requested = 0 }
        if ($requested -le 0) { Write-Status 'Invalid quantity.' Red; continue }
        if (($choice -eq '4' -or $choice -eq '2') -and $requested -gt $plusCeiling) { $requested = $plusCeiling }
        if (-not $sessionStarted) { Write-SessionHeader $logPath 'Legacy'; $sessionStarted = $true }
        Invoke-Generation $modeList $requested $assocCache $ApprovedVerbs $rnd $cwd $logPath $plusCeiling
    } catch {
            Write-CurrentErrorsToLog
            Write-Status "An unexpected error occurred. See errors-log.txt for details." Red
        }
    }
    exit
}

if (Test-HasText $Mode) {
    if (-not $sessionStarted) { Write-SessionHeader $logPath 'Normal'; $sessionStarted = $true }
    $modeKey = ($Mode + '').Trim().ToLower()
    if ($modeKey -eq 'debug') { Invoke-DebugGeneration $assocCache $rnd $cwd $logPath; exit }
    switch ($modeKey) { 'classic' { $modeList = @('classic') } 'plus' { $modeList = @('plus') } 'both' { $modeList = @('classic','plus') } default { $modeList = @('classic') } }
    Invoke-Generation $modeList ([Math]::Max(1,$Count)) $assocCache $ApprovedVerbs $rnd $cwd $logPath $plusCeiling
    exit
}

while ($true) {
    try {
        Write-Host 'Choose mode:'
        Write-Host '1 = Classic'
        Write-Host '2 = Plus'
        Write-Host '3 = Exit'
        Write-Host '4 = Both'
        Write-Host '5 = Debug'
        Write-Host '6 = Info'
        Write-Host '7 = Schedule Task'
        Write-Host '8 = About'
        Write-Host '9 = Create Shortcut'
        Write-Host '0 = Window Mode'
        $choice = Read-Host 'Enter key'
        if ($choice -eq '3') { break }
        if ($choice -eq '6') { Show-InfoMode; continue }
        if ($choice -eq '7') { Invoke-ScheduledTaskMode; continue }
        if ($choice -eq '8') { Show-AboutMode; continue }
        if ($choice -eq '9') { Invoke-SelfShortcutMode; continue }
        if ($choice -eq '0') { Invoke-WindowMode; exit }
        if ($choice -eq '5') {
            if (-not $sessionStarted) {
                Write-SessionHeader $logPath 'Normal'
                $sessionStarted = $true
            }
            Invoke-DebugGeneration $assocCache $rnd $cwd $logPath
            continue
        }
        if ($choice -eq '4') {
            $modeList = @('classic','plus')
        } elseif ($choice -eq '2') {
            $modeList = @('plus')
        } elseif ($choice -eq '1') {
            $modeList = @('classic')
        } else {
            Write-Status 'Invalid choice.' Red
            continue
        }
       $quantityText = Read-Host 'How many files to generate?'
        try { $requested = [int]$quantityText } catch { $requested = 0 }
        if ($requested -le 0) {
            Write-Status 'Invalid quantity.' Red
            continue
        }
        if (($choice -eq '4' -or $choice -eq '2') -and $requested -gt $plusCeiling) {
            $requested = $plusCeiling
        }
        if (-not $sessionStarted) {
            Write-SessionHeader $logPath 'Normal'
            $sessionStarted = $true
        }
        Invoke-Generation $modeList $requested $assocCache $ApprovedVerbs $rnd $cwd $logPath $plusCeiling
    } catch {
        Write-CurrentErrorsToLog
        Write-Status "An unexpected error occurred. See errors-log.txt for details." Red
    }
}

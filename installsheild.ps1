Add-Type -AssemblyName System.Windows.Forms, System.Drawing;

# ==============================================================================
# 1. ENVIRONMENTAL SETTINGS & CACHE PATHS
# ==============================================================================
$winDir          = $env:SystemRoot;
$sys32           = Join-Path $winDir "System32";
$tempPath        = Join-Path $env:TEMP "AeroRaffle_Files";
$cacheTextFile   = Join-Path $env:TEMP "AeroRaffle_DiskStream.txt";
$targetDrive     = [System.IO.Path]::GetPathRoot($winDir);

# Integrated Automatic Self-Wipe
if (Test-Path $tempPath) { 
    Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue;
};
$null = New-Item -Path $tempPath -ItemType Directory -Force -EA 0;

# Native Win32 Subsystem Declarations for Icon Parsing
$api = '[DllImport("shell32.dll")]public static extern uint ExtractIconEx(string f,int i,IntPtr[] l,IntPtr[] s,uint n);';
Add-Type -MemberDefinition $api -Name "W32" -Namespace "API" -EA 0;
$shellApp = New-Object -ComObject Shell.Application;

# ==============================================================================
# 2. HELPER LOGGING & TELEMETRY MODULES
# ==============================================================================
Function Get-RandomDescription {
    Param([System.Collections.Generic.List[string]]$filePool)
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        if ($filePool.Count -eq 0) { break; };
        $randomFile = $filePool | Select-Object -Skip (Get-Random -Min 0 -Max $filePool.Count) -First 1;
        if (-not (Test-Path $randomFile)) { continue; };
        $folderObj = $shellApp.NameSpace((Split-Path $randomFile));
        $fileObj = $folderObj.ParseName((Split-Path $randomFile -Leaf));
        $description = $folderObj.GetDetailsOf($fileObj, 34);
        if (-not [string]::IsNullOrWhiteSpace($description) -and $description -notmatch "^\d+$") { return $description; };
    };
    return "System Component Asset";
}

Function Append-Log {
    Param([string]$msg)
    $logBox.AppendText($msg + [System.Environment]::NewLine);
    $logBox.SelectionStart = $logBox.Text.Length;
    $logBox.ScrollToCaret();
}

# ==============================================================================
# 3. WIN32 INSTALLER-STYLE USER INTERFACE
# ==============================================================================
$w = New-Object System.Windows.Forms.Form;
$w.Text = "Raffle Setup Maintenance Engine v5.5";
$w.Size = New-Object System.Drawing.Size(540, 400);
$w.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog;
$w.MaximizeBox = $false; $w.MinimizeBox = $false; $w.TopMost = $true;
$w.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen;
$w.BackColor = [System.Drawing.Color]::FromArgb(243, 243, 243);

$l = New-Object System.Windows.Forms.Label;
$l.Text = "Initializing Automated System Deployment...";
$l.Location = New-Object System.Drawing.Point(20, 15);
$l.Size = New-Object System.Drawing.Size(480, 20);
$l.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold);
$w.Controls.Add($l);

$logBox = New-Object System.Windows.Forms.TextBox;
$logBox.Location = New-Object System.Drawing.Point(20, 45);
$logBox.Size = New-Object System.Drawing.Size(485, 230);
$logBox.Multiline = $true; $logBox.ReadOnly = $true;
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical;
$logBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30);
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220);
$logBox.Font = New-Object System.Drawing.Font("Consolas", 8.5);
$w.Controls.Add($logBox);

$pb = New-Object System.Windows.Forms.ProgressBar;
$pb.Location = New-Object System.Drawing.Point(20, 290);
$pb.Size = New-Object System.Drawing.Size(485, 24);
$pb.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee;
$pb.MarqueeAnimationSpeed = 30;
$w.Controls.Add($pb);

$w.Show();

Append-Log "InstallShield: Initializing wizard setup configuration...";
Append-Log "Checking target platform disk parameters... [OK]";
Append-Log "Target output repository path: $tempPath";

# ==============================================================================
# 4. ICON EXTRACTION ENGINE
# ==============================================================================
$ic = New-Object System.Collections.Generic.List[string];
$descFiles = New-Object System.Collections.Generic.List[string];

$initialScanFiles = Get-ChildItem (Join-Path $sys32 "*.dll"), (Join-Path $sys32 "*.exe"), (Join-Path $sys32 "*.cpl") -EA 0;
foreach ($file in $initialScanFiles) {
    $descFiles.Add($file.FullName);
    $cnt = [API.W32]::ExtractIconEx($file.FullName, -1, $null, $null, 0);
    if ($cnt -gt 0) { 
        for ($x=0; $x -lt [System.Math]::Min($cnt, 50); $x++) { $ic.Add("$($file.FullName),$x"); }; 
    };
}
if ($ic.Count -eq 0) { $ic.Add((Join-Path $sys32 "shell32.dll") + ",0"); };

# ==============================================================================
# 5. SEQUENTIAL MULTI-JOB DISK STREAM CATALOGER (SLICED WORKER MODES)
# ==============================================================================
if (-not (Test-Path $cacheTextFile)) {
    $l.Text = "Streaming partition paths dynamically to disk...";
    Append-Log "Cache absent. Initializing split sequential scanning pipeline...";
    
    [System.IO.File]::WriteAllText($cacheTextFile, "");
    
    try { 
        $rootDirs = [System.IO.Directory]::GetDirectories($targetDrive);
    } catch { 
        $rootDirs = @();
    };
    
    $jobBlock = {
        Param($dir, $outPath, $throttleHeavy);
        $stream = New-Object System.IO.StreamWriter($outPath, $true, [System.Text.Encoding]::UTF8);
        $queue = New-Object System.Collections.Generic.Queue[string];
        $queue.Enqueue($dir);
        
        $chunkCounter = 0;
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue();
            try {
                $discoveredFiles = [System.IO.Directory]::GetFiles($current, "*", [System.IO.SearchOption]::TopDirectoryOnly);
                foreach ($item in $discoveredFiles) { 
                    $stream.WriteLine($item);
                };
            } catch {}
            try {
                $discoveredDirs = [System.IO.Directory]::GetDirectories($current, "*", [System.IO.SearchOption]::TopDirectoryOnly);
                foreach ($dRef in $discoveredDirs) { 
                    $queue.Enqueue($dRef);
                };
            } catch {}
            
            if ($throttleHeavy) {
                $chunkCounter++;
                if ($chunkCounter -ge 10) {
                    $chunkCounter = 0;
                    [System.Threading.Thread]::Sleep(20);
                };
            };
        };
        $stream.Close();
        $stream.Dispose();
    };
    
    foreach ($directory in $rootDirs) {
        $dirName = [System.IO.Path]::GetFileName($directory);
        $isHeavy = ($dirName -match "WinSxS" -or $dirName -match "SysWOW64");
        
        Append-Log "Initializing segment scan for catalog workspace: \$dirName";
        if ($isHeavy) { Append-Log " -> Enforcing staggered 10-folder chunk restriction limits..."; };
        
        $currentJob = Start-Job -ScriptBlock $jobBlock -ArgumentList $directory, $cacheTextFile, $isHeavy;
        
        while ($currentJob.State -eq "Running") {
            [System.Windows.Forms.Application]::DoEvents();
            Start-Sleep -Milliseconds 100;
        };
        
        Remove-Job -Job $currentJob -Force;
        Append-Log " -> Successfully cataloged and committed folder: \$dirName [OK]";
    };
    Append-Log "All root directory partitions successfully processed and written to disk.";
} else {
    Append-Log "Verified local file system disk stream cache discovered. Loading logs.";
}

# ==============================================================================
# 6. PARSE INDEX STREAM DIRECTLY TO TARGET SHORTCUTS
# ==============================================================================
Append-Log "Beginning shortcut allocation pass...";

$cats = [ordered]@{ 
    "Executables"           = @{ext=".exe"; min=20; max=60; pool=New-Object System.Collections.Generic.List[string]};
    "Control Panel Items"   = @{ext=".cpl"; min=5;  max=15; pool=New-Object System.Collections.Generic.List[string]};
    "Management Consoles"   = @{ext=".msc"; min=10; max=25; pool=New-Object System.Collections.Generic.List[string]};
    "Screen Savers"         = @{ext=".scr"; min=3;  max=10; pool=New-Object System.Collections.Generic.List[string]};
    "Miscellaneous"         = @{ext="all";  min=5;  max=10; pool=New-Object System.Collections.Generic.List[string]};
};

$reader = New-Object System.IO.StreamReader($cacheTextFile, [System.Text.Encoding]::UTF8);
while (($line = $reader.ReadLine()) -ne $null) {
    $fileExt = [System.IO.Path]::GetExtension($line).ToLower();
    
    foreach ($catName in $cats.Keys) {
        $c = $cats[$catName];
        if ($c.ext -eq $fileExt) {
            if ($c.pool.Count -lt 150) { $c.pool.Add($line); };
        };
    };
    if ($cats["Miscellaneous"].pool.Count -lt 150 -and (Get-Random -Min 0 -Max 100) -le 2) {
        $cats["Miscellaneous"].pool.Add($line);
    };
}
$reader.Close(); $reader.Dispose();

$cplSubMenus = @(
    "timedate.cpl,,0|Date and Time Settings", "timedate.cpl,,1|Additional Time Zones", "timedate.cpl,,2|Internet Time sync",
    "sysdm.cpl,,0|Computer Identities", "sysdm.cpl,,1|Hardware Device Profiles", "sysdm.cpl,,2|Advanced System Settings",
    "sysdm.cpl,,3|System Restore Points", "sysdm.cpl,,4|Remote Desktop Settings", "mmsys.cpl,,0|Playback Sound Devices",
    "mmsys.cpl,,1|Recording Inputs Matrix", "mmsys.cpl,,2|Windows System Sounds", "mmsys.cpl,,3|Volume Communications Ducking",
    "main.cpl,,0|Mouse Hardware Buttons", "main.cpl,,1|Mouse Pointers Custom Configuration", "main.cpl,,2|Mouse Pointer Motion Options",
"main.cpl,,3|Mouse Scroll Wheel Settings", "main.cpl,,4|Mouse Hardware Interface Details", "inetcpl.cpl,,0|General Internet Options","inetcpl.cpl,,1|Internet Security Options", "inetcpl.cpl,,2|Privacy Preferences and Blocking", "inetcpl.cpl,,3|Content Security Certificates","inetcpl.cpl,,4|Network Connections Setup", "inetcpl.cpl,,5|Default Program Intercept Customization", "inetcpl.cpl,,6|Advanced Internet Security Framework","appwiz.cpl,,0|Uninstall or Change a Program Menu", "appwiz.cpl,,1|Turn Windows Features On or Off", "powercfg.cpl|System Power Saving Schemes","hdwwiz.cpl|Device Manager Hardware Menu", "firewall.cpl|Windows Defender Firewall Security", "wscui.cpl|Security and Maintenance Center");foreach ($cplApp in $cplSubMenus) {$cats["Control Panel Items"].pool.Add($cplApp);};$wsh = New-Object -ComObject WScript.Shell;$totalTargetsCount = 0;$processedCount = 0;foreach ($cName in $cats.Keys) {$d = $cats.$cName;$totalTargetsCount += [System.Math]::Min((Get-Random -Min $d.min -Max ($d.max + 1)), [System.Math]::Min($d.pool.Count, $ic.Count));};foreach ($cName in $cats.Keys) {$d = $cats.$cName;$p = New-Item -Path (Join-Path $tempPath $cName) -ItemType Directory -Force -EA 0;Append-Log "Generating installation directory folder: $cName";$pl = New-Object System.Collections.Generic.List[string];foreach ($item in $d.pool) {$pl.Add($item);};$co = Get-Random -Min $d.min -Max ($d.max + 1);if ($co -gt $pl.Count) { $co = $pl.Count; };if ($co -gt $ic.Count) { $co = $ic.Count; };while ($co -gt 0 -and $pl.Count -gt 0 -and $ic.Count -gt 0) {$tg = $pl | Select-Object -Skip (Get-Random -Min 0 -Max $pl.Count) -First 1;$null = $pl.Remove($tg);$i = $ic | Select-Object -Skip (Get-Random -Min 0 -Max $ic.Count) -First 1;$null = $ic.Remove($i);try {if ($cName -eq "Miscellaneous") {$shortcutName = "$($p.FullName)\Shortcut To $(Split-Path $tg -Leaf).lnk";$lnk = $wsh.CreateShortcut($shortcutName);$lnk.TargetPath = $tg;} elseif ($cName -eq "Control Panel Items") {$parts = $tg.Split('|');$cplArgs = $parts[0];$friendlyName = $parts[1];$shortcutName = "$($p.FullName)\Shortcut To $friendlyName.lnk";$lnk = $wsh.CreateShortcut($shortcutName);$lnk.TargetPath = "control.exe";$lnk.Arguments = $cplArgs;} else {$shortcutName = "$($p.FullName)\Shortcut To $([System.IO.Path]::GetFileNameWithoutExtension($tg)).lnk";$lnk = $wsh.CreateShortcut($shortcutName);$lnk.TargetPath = $tg;};$lnk.IconLocation = $i;$lnk.Description = Get-RandomDescription -filePool $descFiles;$lnk.Save();$co--;$processedCount++;$l.Text = "Assembling Components: Processing $cName...";Append-Log "  Extract component asset: $(Split-Path $tg -Leaf)... 100%";} catch {}}}
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";Set-ItemProperty -Path $regPath -Name "IconsOnly" -Value 0 -EA 0;Append-Log "Updating Windows Desktop User Interface properties... [OK]";$w.Close();[System.Windows.Forms.MessageBox]::Show("Installation completed successfully!`nOpening package deployment directory...", "Process Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]::ServiceNotification);Start-Process explorer.exe -ArgumentList $tempPath;
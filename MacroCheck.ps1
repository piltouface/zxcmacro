$SelfUrl = 'https://raw.githubusercontent.com/sweetvata/Y-macro/main/MacroCheck.ps1'
$Days = 30
if ($env:YMC_DAYS) { $Days = [int]$env:YMC_DAYS }
$AllDrives = [bool]$env:YMC_ALLDRIVES
$NoPause = [bool]$env:YMC_NOPAUSE
$ExtraRoots = @()
if ($env:YMC_ROOTS) { $ExtraRoots = @($env:YMC_ROOTS -split ';') }

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}
try {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class YMcon {
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint m);
    public static void EnableVt() { IntPtr h = GetStdHandle(-11); uint m; if (GetConsoleMode(h, out m)) SetConsoleMode(h, m | 4); }
}
"@
    [YMcon]::EnableVt()
} catch {}

$esc = [char]27
$pink = "$esc[38;2;255;182;193m"
$reset = "$esc[0m"
function Write-Pink { param([string]$Text); Write-Host "${pink}${Text}${reset}" }

$GlyphMap = [ordered]@{ '#' = [char]0x2588; '1' = [char]0x2557; '2' = [char]0x2554; '3' = [char]0x255D; '4' = [char]0x255A; '|' = [char]0x2551; '=' = [char]0x2550 }

function Show-Banner {
    $c1 = "$esc[1;38;2;255;182;193m"; $c2 = "$esc[38;2;150;110;125m"; $c0 = "$esc[0m"
    $g = @{
        'Y' = @('##1   ##1', '4##1 ##23', ' 4####23 ', '  4##23  ', '   ##|   ', '   4=3   ')
        '-' = @('        ', '        ', '#####1  ', '4====3  ', '        ', '        ')
        'M' = @('###1   ###1', '####1 ####|', '##2####2##|', '##|4##23##|', '##| 4=3 ##|', '4=3     4=3')
        'A' = @(' #####1 ', '##2==##1', '#######|', '##2==##|', '##|  ##|', '4=3  4=3')
        'C' = @(' ######1', '##2====3', '##|     ', '##|     ', '4######1', ' 4=====3')
        'R' = @('######1 ', '##2==##1', '######23', '##2==##1', '##|  ##|', '4=3  4=3')
        'O' = @(' ######1 ', '##2===##1', '##|   ##|', '##|   ##|', '4######23', ' 4=====3 ')
    }
    Write-Host ''
    for ($i = 0; $i -lt 6; $i++) {
        $line = '  '
        foreach ($ch in 'Y', '-', 'M', 'A', 'C', 'R', 'O') { $line += $g[$ch][$i] }
        foreach ($k in $GlyphMap.Keys) { $line = $line.Replace($k, [string]$GlyphMap[$k]) }
        Write-Host "$c1$line$c0"
    }
    Write-Host "$c2  macro / autoclicker checker  -  game screenshare$c0"
    Write-Host ''
}
Show-Banner

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$SelfPath = $MyInvocation.MyCommand.Path
if (-not $IsAdmin) {
    Write-Host 'ERROR: Run as Administrator!' -ForegroundColor Red
    if (-not $NoPause) {
        Write-Host 'Requesting elevation...' -ForegroundColor Gray
        $relaunch = if ($SelfPath) { @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $SelfPath + '"')) } else { @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', ('"irm ' + $SelfUrl + ' | iex"')) }
        try { Start-Process powershell.exe -Verb RunAs -ArgumentList $relaunch; exit 0 } catch { Write-Host 'Elevation was declined.' -ForegroundColor Red }
        if ([Environment]::UserInteractive) { Read-Host 'Press Enter to exit' | Out-Null }
    }
    exit 1
}

$Now = Get-Date
$CutRecent = $Now.AddDays(-$Days)
$CutDay = $Now.AddDays(-1)
$SelfPath = $MyInvocation.MyCommand.Path
$Findings = New-Object System.Collections.Generic.List[object]
$Rank = @{ High = 3; Medium = 2; Low = 1 }
$Latin1 = [Text.Encoding]::GetEncoding(28591)
$script:FoundN = 0
$script:FoundMark = 0

function Open-Section {
    param([string]$Title)
    Write-Pink ("`n" + $Title)
    $script:FoundMark = $script:FoundN
}

function Close-Section {
    if ($script:FoundN -eq $script:FoundMark) { Write-Host '  None' -ForegroundColor Green }
}

function Add-Finding {
    param([string]$Cat, [string]$Level, [string]$Title, [string]$Detail, [string]$Path, $Time)
    $stamp = ''
    if ($Time) { $stamp = ([datetime]$Time).ToString('yyyy-MM-dd HH:mm') }
    $Findings.Add([pscustomobject]@{ Category = $Cat; Level = $Level; Title = $Title; Detail = $Detail; Path = $Path; Time = $stamp })
    $script:FoundN++
    $col = switch ($Level) { 'High' { 'Red' } 'Medium' { 'White' } default { 'Gray' } }
    $line = '  {0,-6} {1}' -f $Level.ToUpper(), $Title
    if ($stamp) { $line += '  (' + $stamp + ')' }
    Write-Host $line -ForegroundColor $col
    if ($Detail) { Write-Host ('         ' + $Detail) -ForegroundColor White }
    if ($Path) { Write-Host ('         ' + $Path) -ForegroundColor Gray }
}

function Read-Head {
    param([string]$Path, [int]$Max = 1048576)
    try {
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $len = [int][Math]::Min($fs.Length, $Max)
            $buf = New-Object byte[] $len
            [void]$fs.Read($buf, 0, $len)
            return $Latin1.GetString($buf)
        } finally { $fs.Dispose() }
    } catch { return $null }
}

function Get-Rot13 {
    param([string]$s)
    $o = New-Object char[] $s.Length
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($c -ge 'a' -and $c -le 'z') { $o[$i] = [char]((([int]$c - 97 + 13) % 26) + 97) }
        elseif ($c -ge 'A' -and $c -le 'Z') { $o[$i] = [char]((([int]$c - 65 + 13) % 26) + 65) }
        else { $o[$i] = $c }
    }
    -join $o
}

$ToolNames = @(
    'autohotkey', 'autohotkey32', 'autohotkey64', 'autohotkeyu64', 'autohotkeyu32', 'autoit3', 'autoit3_x64',
    'tinytask', 'jitbit', 'macrorecorder', 'gsautoclicker', 'opautoclicker', 'autoclicker', 'murgee',
    'pulover', 'macrocreator', 'xmousebuttoncontrol', 'rewasd', 'ds4windows', 'inputmapper', 'antimicro',
    'joy2key', 'keymousego', 'ghostmouse', 'clickermann', 'speedautoclicker', 'fastclicker', 'rapidclicker',
    'clickbot', 'mouserecorder', 'macroexpress', 'perfectmacro', 'keyran', 'autoclick', 'jitterclick',
    'macroplayer', 'mousemacro', 'free mouse auto clicker',
    'recoil', 'norecoil', 'antirecoil', 'rapidfire', 'rapid fire', 'dragclick', 'drag click', 'bhop', 'spammer',
    'keyspam', 'autopresser', 'keypresser', 'autokey', 'robotjs', 'actionaz', 'automouse', 'mouserobot', 'macrotoolworks',
    'quickmacro', 'razermacro', 'jitter', 'autofire', 'autoclick', 'clicker'
)
$ToolRegex = '(?i)(' + (($ToolNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
$StrongTools = '(?i)(autohotkey|autoit3|tinytask|autoclicker|gsautoclicker|opautoclicker|jitbit|macrorecorder|pulover|rapidclicker|fastclicker|clickbot|jitterclick|ghostmouse|keymousego|norecoil|antirecoil|rapidfire|dragclick|autofire)'
$MacroExt = '(?i)\.(ahk|au3|mcr|amc2|kbs|cuecfg)$'
$MacroExtStrict = '(?i)\.(ahk|au3|mcr|amc2|kbs)$'

$VidMap = @{
    '046D' = 'Logitech'; '1532' = 'Razer'; '1038' = 'SteelSeries'; '1B1C' = 'Corsair'; '0B05' = 'ASUS'
    '1E7D' = 'ROCCAT'; '09DA' = 'A4Tech/Bloody'; '258A' = 'Glorious/Sinowealth'
    '2516' = 'Cooler Master'; '03F0' = 'HyperX/HP'; '0951' = 'HyperX/Kingston'; '04D9' = 'Holtek (Redragon etc)'
    '1EA7' = 'SHARKOON/Holtek'; '3554' = 'Attack Shark/VXE'; '373B' = 'Finalmouse'; '31E3' = 'Wooting'
    '25A7' = 'Areson/Rapoo'; '24AE' = 'Rapoo'; '0458' = 'Genius/KYE'; '045E' = 'Microsoft'; '413C' = 'Dell'
}
$OemVids = @('045E', '413C', '04CA', '0461', '093A', '1A2C', '05AC')

$Vendors = @(
    @{ Name = 'Logitech'; Vid = '046D'; Proc = 'lghub|lghub_agent|lghub_updater|lcore|lgs'; Soft = 'Logitech G HUB|Logitech Gaming Software|Logitech Options'
       Paths = @('%LOCALAPPDATA%\LGHUB', '%PROGRAMFILES%\LGHUB', '%LOCALAPPDATA%\Logitech\Logitech Gaming Software', '%APPDATA%\Logitech\Logitech Gaming Software') }
    @{ Name = 'Razer'; Vid = '1532'; Proc = 'razer synapse|razercentralservice|razersynapse|rzsynapse|razer central'; Soft = 'Razer Synapse|Razer Central'
       Paths = @('%LOCALAPPDATA%\Razer\Synapse3\Log', '%PROGRAMDATA%\Razer\Synapse3\Accounts', '%APPDATA%\Razer', '%LOCALAPPDATA%\Razer', '%PROGRAMDATA%\Razer', '%PROGRAMFILES(X86)%\Razer') }
    @{ Name = 'SteelSeries'; Vid = '1038'; Proc = 'steelseriesgg|steelseriesengine|steelseriesgghelper'; Soft = 'SteelSeries GG|SteelSeries Engine'
       Paths = @('%PROGRAMDATA%\SteelSeries', '%LOCALAPPDATA%\SteelSeries', '%APPDATA%\steelseries-engine-3-client', '%LOCALAPPDATA%\steelseries-engine-3-client') }
    @{ Name = 'Corsair'; Vid = '1B1C'; Proc = 'icue|corsair'; Soft = 'iCUE|Corsair'
       Paths = @('%APPDATA%\Corsair', '%LOCALAPPDATA%\Corsair', '%PROGRAMDATA%\Corsair') }
    @{ Name = 'ASUS ROG'; Vid = '0B05'; Proc = 'armourycrate|armourysocketserver|asusappservice|rog armoury|asuscertservice|lightingservice'; Soft = 'Armoury Crate|ROG Armoury|ASUS'
       Paths = @('%USERPROFILE%\Documents\ASUS\ROG\ROG Armoury\common', '%LOCALAPPDATA%\ASUS', '%PROGRAMDATA%\ASUS', '%PROGRAMFILES%\ASUS\ARMOURY CRATE Service') }
    @{ Name = 'ROCCAT'; Vid = '1E7D'; Proc = 'roccat|swarm'; Soft = 'ROCCAT Swarm'
       Paths = @('%APPDATA%\ROCCAT\SWARM\macro', '%APPDATA%\ROCCAT') }
    @{ Name = 'Bloody/A4Tech'; Vid = '09DA'; Proc = 'bloody7|bloody'; Soft = 'Bloody'
       Paths = @('%PROGRAMFILES(X86)%\Bloody7\Bloody7\Data\Mouse\English\ScriptsMacros\GunLib', '%PROGRAMFILES(X86)%\Bloody7', '%PROGRAMFILES%\Bloody7', '%APPDATA%\Bloody7') }
    @{ Name = 'Glorious'; Vid = '258A'; Proc = 'gloriouscore|glorious'; Soft = 'Glorious Core|Glorious'
       Paths = @('%APPDATA%\BY-COMBO2', '%APPDATA%\BYCOMBO-2', '%APPDATA%\Glorious Core', '%LOCALAPPDATA%\Glorious Core') }
    @{ Name = 'Redragon'; Vid = '04D9'; Proc = 'redragon|gaming mouse'; Soft = 'Redragon|Gaming Mouse'
       Paths = @('%USERPROFILE%\Documents\M* Gaming Mouse\MacroDB', '%USERPROFILE%\Documents\Redragon*') }
    @{ Name = 'Cooler Master'; Vid = '2516'; Proc = 'masterplus|coolermaster'; Soft = 'MasterPlus|Cooler Master'
       Paths = @('%LOCALAPPDATA%\CoolerMaster', '%APPDATA%\CoolerMaster', '%PROGRAMDATA%\CoolerMaster') }
    @{ Name = 'HyperX'; Vid = '03F0'; Proc = 'ngenuity|hyperx'; Soft = 'NGENUITY|HyperX'
       Paths = @('%LOCALAPPDATA%\HyperX', '%APPDATA%\HyperX', '%PROGRAMDATA%\HyperX') }
    @{ Name = 'Attack Shark/VXE'; Vid = '3554'; Proc = 'attackshark|vxe'; Soft = 'Attack Shark|VXE'
       Paths = @('%APPDATA%\AttackShark*', '%LOCALAPPDATA%\AttackShark*') }
    @{ Name = 'Krom/Ayax/MotoSpeed'; Vid = ''; Proc = 'krom|ayax|motospeed'; Soft = 'KROM|AYAX|MotoSpeed'
       Paths = @('%LOCALAPPDATA%\VirtualStore\Program Files (x86)\KROM KOLT\Config', '%PROGRAMFILES%\AYAX GamingMouse', '%PROGRAMFILES(X86)%\MotoSpeed Gaming Mouse\V60\modules') }
)

$MarkerRegex = '(?i)("macros?"|macroData|macroManager|<macro|\[macro|macro=|"keyAction"|"actions"\s*:|<action|<delay|"assignments"|RecMouseClick|MemberFuncSlot|sequence)'
$SkipDirs = @(
    'node_modules', 'site-packages', '.git', '__pycache__', 'uv', 'pip', 'npm-cache', '.cache', '.nuget', '.cargo', '.rustup',
    '.gradle', '.m2', 'windowsapps', 'microsoft', '.vscode', 'cache', 'gpucache', 'code cache', 'crashpad', 'packages',
    'claude', '.claude', 'temp', 'inetcache', 'history', 'webcache', 'steamapps', 'epic games', 'lib', 'venv', '.venv', 'conda', 'anaconda3', 'miniconda3'
)
$SkipSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($d in $SkipDirs) { [void]$SkipSet.Add($d.ToLower()) }

function Expand-Pattern {
    param([string]$p)
    $e = [Environment]::ExpandEnvironmentVariables($p)
    if ($e -match '[\*\?]') { @(Get-Item -Path $e -Force) | ForEach-Object { $_.FullName } }
    elseif (Test-Path -LiteralPath $e) { $e }
}

function Get-FilesWalk {
    param([string[]]$Roots, $Exts, $Names)
    $stack = New-Object System.Collections.Stack
    foreach ($r in $Roots) { if ($r -and (Test-Path -LiteralPath $r)) { $stack.Push($r) } }
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($d)) {
                $e = [IO.Path]::GetExtension($f).ToLower()
                $n = [IO.Path]::GetFileName($f).ToLower()
                if ($Exts.Contains($e) -or $Names.Contains($n) -or $n -match $ToolRegex) { $f }
            }
        } catch {}
        try {
            foreach ($s in [IO.Directory]::EnumerateDirectories($d)) {
                $leaf = [IO.Path]::GetFileName($s).ToLower()
                if ($SkipSet.Contains($leaf)) { continue }
                try { if (([IO.File]::GetAttributes($s) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue } } catch { continue }
                $stack.Push($s)
            }
        } catch {}
    }
}

$KeywordSets = @{
    '.ahk'  = @{ Words = 'SendInput|SendEvent|SendPlay|Send|Click|MouseClick|MouseClickDrag|SetKeyDelay|SetMouseDelay|GetKeyState|Hotkey|SetTimer|#InstallMouseHook|#InstallKeybdHook|XButton1|XButton2|LButton|RButton|BlockInput|ControlClick|Sleep'; Need = 'SendInput|SendEvent|SendPlay|Send|Click|MouseClick|LButton|RButton|ControlClick'; Min = 3 }
    '.au3'  = @{ Words = 'MouseClick|MouseDown|MouseUp|MouseMove|ControlClick|HotKeySet|Send|Sleep|_IsPressed|AdlibRegister'; Need = 'MouseClick|MouseDown|ControlClick|Send'; Min = 3 }
    '.py'   = @{ Words = 'pyautogui|pydirectinput|pynput|mouse_event|SendInput|SetCursorPos|GetAsyncKeyState|win32api|autoclick|click_delay|cps|click\(|while True|time\.sleep|random\.uniform'; Need = 'pyautogui|pydirectinput|pynput|mouse_event|SendInput|SetCursorPos|autoclick'; Min = 2 }
    '.pyw'  = @{ Words = 'pyautogui|pydirectinput|pynput|mouse_event|SendInput|SetCursorPos|GetAsyncKeyState|win32api|autoclick|click_delay|cps|click\(|while True|time\.sleep|random\.uniform'; Need = 'pyautogui|pydirectinput|pynput|mouse_event|SendInput|SetCursorPos|autoclick'; Min = 2 }
    '.lua'  = @{ Words = 'PressMouseButton|ReleaseMouseButton|PressAndReleaseMouseButton|IsMouseButtonPressed|OnEvent|MoveMouseRelative|EnablePrimaryMouseButtonEvents|Sleep'; Need = 'PressMouseButton|ReleaseMouseButton|PressAndReleaseMouseButton|IsMouseButtonPressed|EnablePrimaryMouseButtonEvents'; Min = 2 }
    '.vbs'  = @{ Words = 'SendKeys|mouse_event|SetCursorPos|GetAsyncKeyState|keybd_event|SendInput|user32'; Need = 'mouse_event|SetCursorPos|SendInput|SendKeys'; Min = 2 }
    '.ps1'  = @{ Words = 'SendKeys|mouse_event|SetCursorPos|GetAsyncKeyState|keybd_event|SendInput|user32\.dll'; Need = 'mouse_event|SetCursorPos|SendInput'; Min = 2 }
    '.cfg'  = @{ Words = 'alias|wait|mwheeldown|mwheelup|attack|jump|duck|bind'; Need = 'mwheeldown|mwheelup'; Min = 4 }
    '.js'   = @{ Words = 'robotjs|nut-tree|iohook|keyTap|mouseClick|setMouseDelay|moveMouse'; Need = 'robotjs|nut-tree|iohook'; Min = 1 }
    '.cuecfg' = @{ Words = 'RecMouseClick|macro|MemberFuncSlot'; Need = 'RecMouseClick|macro'; Min = 1 }
}
$BinaryMacroExt = '.mcr', '.amc2', '.kbs', '.pmc', '.tcs', '.rxrec', '.atmx', '.xnr', '.kmmacros'

$Exts = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($k in $KeywordSets.Keys) { [void]$Exts.Add($k) }
foreach ($k in $BinaryMacroExt) { [void]$Exts.Add($k) }
$Names = New-Object 'System.Collections.Generic.HashSet[string]'
[void]$Names.Add('interception.dll')

function Get-ScriptHits {
    param([string]$Ext, [string]$Text)
    $ks = $KeywordSets[$Ext]
    if (-not $ks -or -not $Text -or $Text.Contains('macro / autoclicker checker')) { return $null }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($w in ($ks.Words -split '\|')) {
        $rx = if ($w.StartsWith('#')) { '(?i)' + [regex]::Escape($w) } else { '(?i)(?<![A-Za-z0-9_])' + $w + '(?![A-Za-z0-9_])' }
        if ([regex]::IsMatch($Text, $rx)) { $found.Add($w) }
    }
    if ($found.Count -lt $ks.Min) { return $null }
    $needOk = $false
    foreach ($w in $found) { if ($w -match ('^(' + $ks.Need + ')$')) { $needOk = $true } }
    if (-not $needOk) { return $null }
    [pscustomobject]@{ Found = $found; Min = $ks.Min }
}

Write-Pink 'MOUSE DEVICES'
$seen = @{}
$activeVendors = @{}
$connectedAny = $false
foreach ($m in @(Get-CimInstance Win32_PointingDevice)) {
    $vid = ''
    if ($m.PNPDeviceID -match 'VID_([0-9A-F]{4})') { $vid = $Matches[1] }
    $vendor = if ($vid -and $VidMap.ContainsKey($vid)) { $VidMap[$vid] } else { $m.Manufacturer }
    if ($seen.ContainsKey($m.PNPDeviceID)) { continue }
    $seen[$m.PNPDeviceID] = 1
    $connectedAny = $true
    Write-Host ('  Connected : {0} | {1} | VID {2}' -f $m.Name, $vendor, $vid) -ForegroundColor White
    if ($vid) { $activeVendors[$vid] = 1 }
}
$histVids = @{}
foreach ($root in 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID', 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB') {
    foreach ($k in @(Get-ChildItem $root)) {
        if ($k.PSChildName -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') { $histVids[$Matches[1].ToUpper()] = 1 }
    }
}
foreach ($v in $histVids.Keys) {
    if ($VidMap.ContainsKey($v) -and $OemVids -notcontains $v -and -not $activeVendors.ContainsKey($v)) {
        Write-Host ('  History   : {0} | VID {1}' -f $VidMap[$v], $v) -ForegroundColor Gray
        $activeVendors[$v] = 1
    }
}
if (-not $connectedAny -and $histVids.Count -eq 0) { Write-Host '  None' -ForegroundColor Gray }

Write-Pink "`nVENDOR SOFTWARE"
$uninstall = @()
foreach ($u in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    $uninstall += @(Get-ItemProperty $u | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, InstallDate, InstallLocation)
}
$procs = @(Get-Process | Select-Object Name, Id, Path)
$vendorShown = 0
foreach ($v in $Vendors) {
    $inst = @($uninstall | Where-Object { $_.DisplayName -match $v.Soft } | Select-Object -First 3)
    $run = @($procs | Where-Object { $_.Name -match $v.Proc })
    if ($inst.Count -eq 0 -and $run.Count -eq 0) { continue }
    $vendorShown++
    $instNames = ($inst | ForEach-Object { $_.DisplayName }) -join '; '
    $rn = ($run | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', '
    $col = if ($v.Vid -and $activeVendors.ContainsKey($v.Vid)) { 'White' } else { 'Gray' }
    Write-Host ('  {0,-14}: {1}' -f $v.Name, $instNames) -ForegroundColor $col
    if ($rn) { Write-Host ('  {0,-14}  running: {1}' -f '', $rn) -ForegroundColor $col }
}
if ($vendorShown -eq 0) { Write-Host '  None' -ForegroundColor Gray }

Open-Section 'VENDOR CONFIGS'
$cfgSeen = @{}
foreach ($v in $Vendors) {
    foreach ($pat in $v.Paths) {
        foreach ($base in @(Expand-Pattern $pat)) {
            $files = @()
            if (Test-Path -LiteralPath $base -PathType Leaf) { $files = @(Get-Item -LiteralPath $base -Force) }
            else {
                $files = @(Get-ChildItem -LiteralPath $base -Recurse -Depth 4 -File -Force | Where-Object {
                    $_.Length -lt 52428800 -and $_.Extension -match '(?i)^\.(json|xml|db|ini|dat|cfg|cuecfg|amc2|lua|txt|log|mac|bin|sqlite|ldb|cfgx|profile)$' -and $_.FullName -notmatch '(?i)\\(cache|gpucache|code cache|crashpad)\\'
                } | Sort-Object LastWriteTime -Descending | Select-Object -First 60)
            }
            foreach ($f in $files) {
                if ($cfgSeen.ContainsKey($f.FullName)) { continue }
                $cfgSeen[$f.FullName] = 1
                $txt = Read-Head $f.FullName 8388608
                if (-not $txt) { continue }
                $hits = [regex]::Matches($txt, $MarkerRegex)
                $macroWord = [regex]::Matches($txt, '(?i)macro').Count
                if ($hits.Count -eq 0 -and $macroWord -eq 0) { continue }
                $distinct = ($hits | ForEach-Object { $_.Value.ToLower() } | Sort-Object -Unique)
                $level = 'Low'
                if ($f.LastWriteTime -ge $CutRecent -and $hits.Count -ge 3) { $level = 'Medium' }
                if ($f.LastWriteTime -ge $CutDay -and $hits.Count -ge 5) { $level = 'High' }
                $detail = '{0}: {1} markers, "macro" x{2}, distinct: {3}' -f $v.Name, $hits.Count, $macroWord, (($distinct | Select-Object -First 6) -join ' ')
                $macroNames = @()
                foreach ($mm in [regex]::Matches($txt, '(?i)"macro[A-Za-z]*"\s*:')) {
                    $seg = $txt.Substring($mm.Index, [Math]::Min(400, $txt.Length - $mm.Index))
                    $nm = [regex]::Match($seg, '(?i)"(?:name|label|title)"\s*:\s*"([^"]{1,60})"')
                    if ($nm.Success) { $macroNames += $nm.Groups[1].Value }
                    if ($macroNames.Count -ge 12) { break }
                }
                if ($macroNames.Count -gt 0) { $detail += '; macro names: ' + (($macroNames | Select-Object -Unique -First 8) -join ', ') }
                Add-Finding 'Vendor config' $level $f.Name $detail $f.FullName $f.LastWriteTime
            }
        }
    }
}
Close-Section

Open-Section 'RUNNING MACRO TOOLS'
foreach ($p in $procs) {
    if ($p.Name -match $ToolRegex) {
        $sig = ''
        if ($p.Path) { $sig = (Get-AuthenticodeSignature -LiteralPath $p.Path).Status }
        $lvl = if ($p.Name -match $StrongTools) { 'High' } else { 'Medium' }
        Add-Finding 'Process' $lvl $p.Name ("pid {0}, signature: {1}" -f $p.Id, $sig) $p.Path $null
    }
}
Close-Section

Open-Section 'INSTALLED MACRO SOFTWARE'
foreach ($u in ($uninstall | Where-Object { $_.DisplayName -match $ToolRegex } | Sort-Object DisplayName -Unique)) {
    $d = $null
    if ($u.InstallDate -match '^\d{8}$') { try { $d = [datetime]::ParseExact($u.InstallDate, 'yyyyMMdd', $null) } catch {} }
    Add-Finding 'Installed' 'Medium' $u.DisplayName ("version {0}" -f $u.DisplayVersion) $u.InstallLocation $d
}
Close-Section

Open-Section 'MACRO FILES AND SCRIPTS'
$roots = @($env:USERPROFILE, $env:ProgramData, 'C:\Users\Public', 'C:\Temp', "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp") + $ExtraRoots
foreach ($dd in [IO.DriveInfo]::GetDrives()) {
    if ($dd.DriveType -eq 'Fixed' -and $dd.IsReady -and ($AllDrives -or $dd.Name.TrimEnd('\') -ne $env:SystemDrive)) { $roots += $dd.RootDirectory.FullName }
}
$roots = $roots | Where-Object { $_ } | Select-Object -Unique
$scanned = 0
$selfNorm = if ($SelfPath) { $SelfPath.ToLower() } else { '' }
foreach ($f in (Get-FilesWalk -Roots $roots -Exts $Exts -Names $Names)) {
    if ($f.ToLower() -eq $selfNorm) { continue }
    $ext0 = [IO.Path]::GetExtension($f).ToLower()
    if (($ext0 -eq '.js' -or $ext0 -eq '.cfg') -and [IO.File]::GetLastWriteTime($f) -lt $CutRecent) { continue }
    if ($ext0 -eq '.js' -and $f -match '\\AppData\\') { continue }
    $scanned++
    $fi = Get-Item -LiteralPath $f -Force
    if (-not $fi) { continue }
    $ext = $fi.Extension.ToLower()
    $recent = $fi.LastWriteTime -ge $CutRecent
    if ($fi.Name -ieq 'interception.dll') {
        Add-Finding 'Input driver' 'Medium' $fi.Name 'Interception library (driver-level input capture and injection)' $fi.FullName $fi.LastWriteTime
        continue
    }
    if ($BinaryMacroExt -contains $ext) {
        Add-Finding 'Macro file' $(if ($recent) { 'Medium' } else { 'Low' }) $fi.Name 'Macro editor file format' $fi.FullName $fi.LastWriteTime
        continue
    }
    if (($ext -in '.zip', '.rar', '.7z', '.msi', '.iso') -and ($fi.Name -match $ToolRegex)) {
        Add-Finding 'Archive' $(if ($recent) { 'Medium' } else { 'Low' }) $fi.Name 'archive or installer with a macro tool name' $fi.FullName $fi.LastWriteTime
        continue
    }
    if ($ext -eq '.exe' -or $ext -eq '.dll' -or $ext -eq '.lnk') {
        if ($fi.Name -match $ToolRegex) {
            $sig = (Get-AuthenticodeSignature -LiteralPath $fi.FullName).Status
            $lvl = if ($fi.Name -match $StrongTools) { 'Medium' } else { 'Low' }
            Add-Finding 'Program file' $lvl $fi.Name ("name matches macro tool list, signature: $sig") $fi.FullName $fi.LastWriteTime
        }
        continue
    }
    if (-not $KeywordSets.ContainsKey($ext) -or $fi.Length -gt 2097152) { continue }
    if (($ext -eq '.js' -or $ext -eq '.cfg') -and -not $recent) { continue }
    $sh = Get-ScriptHits $ext (Read-Head $fi.FullName 262144)
    if (-not $sh) { continue }
    $lvl = if ($recent) { 'Medium' } else { 'Low' }
    if ($sh.Found.Count -ge ($sh.Min + 2) -and $recent) { $lvl = 'High' }
    Add-Finding 'Script' $lvl $fi.Name ("{0} keywords: {1}" -f $sh.Found.Count, ($sh.Found -join ', ')) $fi.FullName $fi.LastWriteTime
}
Close-Section
Write-Host ('  Scanned   : {0} candidate files in {1} roots' -f $scanned, @($roots).Count) -ForegroundColor Gray

Open-Section 'RECYCLE BIN'
foreach ($d in [IO.DriveInfo]::GetDrives()) {
    if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
    $binRoot = $d.Name + '$Recycle.Bin'
    foreach ($bin in @(Get-ChildItem -LiteralPath $binRoot -Force -Directory)) {
        foreach ($it in @(Get-ChildItem -LiteralPath $bin.FullName -Force -File)) {
            if ($it.Name -notmatch '^\$R') { continue }
            $ext = $it.Extension.ToLower()
            $origName = $it.Name
            $origPath = ''
            $deleted = $it.LastWriteTime
            $info = Join-Path $bin.FullName ('$I' + $it.Name.Substring(2))
            if (Test-Path -LiteralPath $info) {
                try {
                    $b = [IO.File]::ReadAllBytes($info)
                    $ver = [BitConverter]::ToInt64($b, 0)
                    $deleted = [DateTime]::FromFileTime([BitConverter]::ToInt64($b, 16))
                    if ($ver -eq 2) { $origPath = [Text.Encoding]::Unicode.GetString($b, 28, $b.Length - 28).TrimEnd([char]0) }
                    else { $origPath = [Text.Encoding]::Unicode.GetString($b, 24, $b.Length - 24).TrimEnd([char]0) }
                    if ($origPath) { $origName = [IO.Path]::GetFileName($origPath) }
                } catch {}
            }
            $recentDel = $deleted -ge $CutRecent
            $dayDel = $deleted -ge $CutDay
            if ($BinaryMacroExt -contains $ext -or $origName -match $MacroExtStrict) {
                Add-Finding 'Recycle' $(if ($dayDel) { 'High' } elseif ($recentDel) { 'Medium' } else { 'Low' }) $origName 'macro file in Recycle Bin' $origPath $deleted
                continue
            }
            if ($origName -match $ToolRegex) {
                Add-Finding 'Recycle' $(if ($recentDel) { 'Medium' } else { 'Low' }) $origName 'macro tool in Recycle Bin' $origPath $deleted
                continue
            }
            if ($KeywordSets.ContainsKey($ext) -and $it.Length -le 2097152) {
                $sh = Get-ScriptHits $ext (Read-Head $it.FullName 262144)
                if ($sh) {
                    $lvl = if ($dayDel -and $sh.Found.Count -ge ($sh.Min + 1)) { 'High' } elseif ($recentDel) { 'Medium' } else { 'Low' }
                    Add-Finding 'Recycle' $lvl $origName ("script in Recycle Bin, {0} keywords: {1}" -f $sh.Found.Count, ($sh.Found -join ', ')) $origPath $deleted
                }
            }
        }
    }
}
Close-Section

Open-Section 'COMPILED SCRIPTS (EXE)'
$exeRoots = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents", 'C:\Users\Public', 'C:\Temp') + $ExtraRoots
$exeSet = New-Object 'System.Collections.Generic.HashSet[string]'
[void]$exeSet.Add('.exe')
$emptyNames = New-Object 'System.Collections.Generic.HashSet[string]'
$exeScanned = 0
foreach ($f in (Get-FilesWalk -Roots $exeRoots -Exts $exeSet -Names $emptyNames)) {
    if ([IO.Path]::GetExtension($f).ToLower() -ne '.exe') { continue }
    $fi = Get-Item -LiteralPath $f -Force
    if (-not $fi -or $fi.Length -lt 102400 -or $fi.Length -gt 12582912 -or $fi.Name -match $ToolRegex) { continue }
    if ($exeScanned -ge 600) { Write-Host '  Limit of 600 executables reached, rest skipped' -ForegroundColor Gray; break }
    $exeScanned++
    $raw = Read-Head $fi.FullName 12582912
    if (-not $raw) { continue }
    $recent = $fi.LastWriteTime -ge $CutRecent
    $ahkCount = [regex]::Matches($raw, 'AutoHotkey').Count
    $au3 = $raw -match '>AUTOIT SCRIPT<|AU3!EA06'
    $toolMentions = 0
    if ($ahkCount -gt 0 -or $au3) { $toolMentions = @($ToolNames | Where-Object { $raw.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count }
    if (($ahkCount -ge 3 -or $au3) -and $toolMentions -lt 4) {
        Add-Finding 'Compiled' $(if ($recent) { 'High' } else { 'Medium' }) $fi.Name ('contains AutoHotkey or AutoIt runtime markers ({0} mentions), compiled script under another name' -f $ahkCount) $fi.FullName $fi.LastWriteTime
    } elseif ($ahkCount -gt 0) {
        Add-Finding 'Compiled' 'Low' $fi.Name ('mentions AutoHotkey {0} time(s) and {1} macro tool names, probably a checker and not a compiled script' -f $ahkCount, $toolMentions) $fi.FullName $fi.LastWriteTime
    } elseif ($raw -match 'pyautogui|pydirectinput|pynput') {
        Add-Finding 'Compiled' $(if ($recent) { 'Medium' } else { 'Low' }) $fi.Name 'bundled Python input automation library (PyInstaller-style exe)' $fi.FullName $fi.LastWriteTime
    }
}
Close-Section
Write-Host ('  Scanned   : {0} executables' -f $exeScanned) -ForegroundColor Gray

Open-Section 'BROWSER DOWNLOADS'
$dlHist = @()
foreach ($bp in '%LOCALAPPDATA%\Google\Chrome\User Data\*\History', '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\History', '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\History', '%APPDATA%\Opera Software\Opera Stable\History', '%APPDATA%\Opera Software\Opera GX Stable\History', '%APPDATA%\Mozilla\Firefox\Profiles\*\places.sqlite') {
    $dlHist += @(Expand-Pattern $bp)
}
$dlRx = '(?i)(?:[A-Za-z]:\\|file:///[A-Za-z]:/)[\x20-\x7e]{0,200}?(?:' + (($ToolNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')[\x20-\x7e]{0,60}'
$dlUnreadable = 0
foreach ($h in $dlHist) {
    $htxt = Read-Head $h 67108864
    if (-not $htxt) { $dlUnreadable++; continue }
    $found = [regex]::Matches($htxt, $dlRx) | ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique | Select-Object -First 8
    foreach ($fm in $found) {
        $lvl = if ($fm -match $StrongTools) { 'Medium' } else { 'Low' }
        Add-Finding 'Download' $lvl ([IO.Path]::GetFileName(($fm -replace '/', '\'))) 'path found in browser download history' $fm $null
    }
}
Write-Host ('  History   : {0} files read, {1} locked' -f (@($dlHist).Count - $dlUnreadable), $dlUnreadable) -ForegroundColor Gray
Close-Section

Open-Section 'EXECUTION TRACES'
$ua = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
foreach ($g in @(Get-ChildItem $ua)) {
    $cnt = Get-Item -Path ($g.PSPath + '\Count')
    if (-not $cnt) { continue }
    foreach ($name in $cnt.GetValueNames()) {
        $dec = Get-Rot13 $name
        if ($dec -notmatch $ToolRegex) { continue }
        $data = $cnt.GetValue($name)
        $last = $null; $runs = 0
        if ($data -is [byte[]] -and $data.Length -ge 68) {
            $runs = [BitConverter]::ToInt32($data, 4)
            $ft = [BitConverter]::ToInt64($data, 60)
            if ($ft -gt 0) { $last = [DateTime]::FromFileTime($ft) }
        }
        $lvl = if ($last -and $last -ge $CutRecent -and $dec -match $StrongTools) { 'High' } elseif ($last -and $last -ge $CutRecent) { 'Medium' } else { 'Low' }
        Add-Finding 'Trace' $lvl 'UserAssist' ("runs: $runs") $dec $last
    }
}
$bam = 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings'
foreach ($sid in @(Get-ChildItem $bam)) {
    $key = Get-Item -Path $sid.PSPath
    foreach ($name in $key.GetValueNames()) {
        if ($name -notmatch $ToolRegex) { continue }
        $data = $key.GetValue($name)
        $last = $null
        if ($data -is [byte[]] -and $data.Length -ge 8) { $last = [DateTime]::FromFileTime([BitConverter]::ToInt64($data, 0)) }
        $lvl = if ($last -and $last -ge $CutRecent) { 'Medium' } else { 'Low' }
        Add-Finding 'Trace' $lvl 'BAM' 'tool from list was executed' $name $last
    }
}
foreach ($pf in @(Get-ChildItem 'C:\Windows\Prefetch' -Filter '*.pf')) {
    if ($pf.Name -notmatch $ToolRegex) { continue }
    $lvl = if ($pf.LastWriteTime -ge $CutRecent) { 'Medium' } else { 'Low' }
    Add-Finding 'Trace' $lvl 'Prefetch' 'tool from list was executed' $pf.FullName $pf.LastWriteTime
}
Close-Section

Open-Section 'RECENT FILES'
$recentDir = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
$wsh = New-Object -ComObject WScript.Shell
foreach ($l in @(Get-ChildItem -LiteralPath $recentDir -Filter '*.lnk' -Force)) {
    $base = $l.BaseName
    if ($base -notmatch $MacroExt -and $base -notmatch $ToolRegex) { continue }
    $target = ''
    try { $target = $wsh.CreateShortcut($l.FullName).TargetPath } catch {}
    $gone = ($target -and -not (Test-Path -LiteralPath $target))
    $isRecent = $l.LastWriteTime -ge $CutRecent
    $lvl = 'Low'
    if ($isRecent) { $lvl = 'Medium' }
    if ($isRecent -and $gone -and $base -match $MacroExt) { $lvl = 'High' }
    $note = if ($gone) { 'target file was deleted or moved' } else { 'target file exists' }
    Add-Finding 'Recent' $lvl $base $note $target $l.LastWriteTime
}
Close-Section

Open-Section 'USN JOURNAL'
$pats = @('.ahk', '.au3', '.mcr', '.amc2', '.kbs') + $ToolNames
$fsArgs = ($pats | ForEach-Object { '/c:"' + $_ + '"' }) -join ' '
$usn = @{}
foreach ($d in [IO.DriveInfo]::GetDrives()) {
    if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady -or $d.DriveFormat -ne 'NTFS') { continue }
    $letter = $d.Name.Substring(0, 2)
    $lines = @(cmd /c ('fsutil usn readjournal ' + $letter + ' csv 2>nul | findstr /i ' + $fsArgs))
    foreach ($ln in $lines) {
        if ($ln -match '^\d+,"([^"]*)",\d+,0x[0-9a-fA-F]+,"([^"]*)","([^"]*)"') {
            $nm = $Matches[1]; $why = $Matches[2]; $ts = $Matches[3]
            if ($nm.StartsWith('$') -or $nm -match '(?i)\.pf$') { continue }
            if ($nm -notmatch $MacroExt -and $nm -notmatch $ToolRegex) { continue }
            $when = $null
            try { $when = [datetime]::Parse($ts, [Globalization.CultureInfo]::CurrentCulture) } catch {}
            $key = $letter + '\' + $nm.ToLower()
            if (-not $usn.ContainsKey($key)) { $usn[$key] = @{ Name = $nm; Drive = $letter; Last = $when; Gone = $false; Why = @{} } }
            $e = $usn[$key]
            if ($when -and (-not $e.Last -or $when -gt $e.Last)) { $e.Last = $when }
            foreach ($w in ($why -split '\s*\|\s*')) { $e.Why[$w] = 1 }
            if ($why -match 'File delete|Rename: old name') { $e.Gone = $true }
        }
    }
}
foreach ($e in $usn.Values) {
    $isMacroFile = $e.Name -match $MacroExtStrict
    $lvl = 'Low'
    if ($e.Gone -and $e.Last -and $e.Last -ge $CutRecent) { $lvl = 'Medium' }
    if ($e.Gone -and $e.Last -and $e.Last -ge $CutDay -and $isMacroFile) { $lvl = 'High' }
    $events = ($e.Why.Keys | Sort-Object) -join '; '
    Add-Finding 'USN' $lvl $e.Name ("events: $events") ("drive " + $e.Drive) $e.Last
}
Close-Section

Open-Section 'STARTUP AND SCHEDULED TASKS'
foreach ($rk in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
    $item = Get-ItemProperty -Path $rk
    if (-not $item) { continue }
    foreach ($prop in $item.PSObject.Properties) {
        if ($prop.Name -like 'PS*') { continue }
        $val = [string]$prop.Value
        if ($val -match $ToolRegex -or $val -match '(?i)\.(ahk|au3)\b') { Add-Finding 'Startup' 'Medium' $prop.Name $val $rk $null }
    }
}
foreach ($t in @(Get-ScheduledTask)) {
    foreach ($a in $t.Actions) {
        $cmdline = ('{0} {1}' -f $a.Execute, $a.Arguments)
        if ($cmdline -match $ToolRegex -or $cmdline -match '(?i)\.(ahk|au3)\b') { Add-Finding 'Task' 'Medium' $t.TaskName $cmdline $t.TaskPath $null }
    }
}
Close-Section

Open-Section 'CORRELATION'
$present = @($Findings | Where-Object { $_.Category -in 'Program file', 'Process', 'Macro file', 'Installed' })
$corrSeen = @{}
foreach ($t in @($Findings | Where-Object { $_.Category -eq 'Trace' })) {
    $tok = ([regex]::Match($t.Path, $ToolRegex).Value).ToLower()
    if (-not $tok -or $corrSeen.ContainsKey($tok)) { continue }
    $corrSeen[$tok] = 1
    $onDisk = @($present | Where-Object { $_.Title.ToLower().Contains($tok) -or $_.Path.ToLower().Contains($tok) })
    if ($onDisk.Count -gt 0) {
        Add-Finding 'Correlation' 'High' $tok 'tool is present or running and execution traces exist' $onDisk[0].Path $t.Time
    } else {
        $lvl = if ($tok -match $StrongTools) { 'High' } else { 'Medium' }
        Add-Finding 'Correlation' $lvl $tok 'tool was executed but its file is not in scanned folders (deleted, moved or outside roots)' $t.Path $t.Time
    }
}
Close-Section

Write-Host "`nzxc did it" -ForegroundColor DarkGray
Write-Host ''

if (-not $NoPause -and $Host.Name -eq 'ConsoleHost' -and [Environment]::UserInteractive) {
    Read-Host 'Press Enter to exit' | Out-Null
}

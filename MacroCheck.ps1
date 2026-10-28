$SelfUrl = 'https://raw.githubusercontent.com/sweetvata/Y-macro/main/MacroCheck.ps1'
$Days = 30
$DevDays = 7
if ($env:YMC_DEVDAYS) { $DevDays = [int]$env:YMC_DEVDAYS }
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
    'quickmacro', 'razermacro', 'jitter', 'autofire', 'autoclick', 'clicker',
    'macrogamer', 'ptfb pro', 'minimousemacro', 'mini mouse macro', 'tgmacro', 'auto keyboard presser', 'perfect automation',
    'easy macro recorder', 'auto click typer', 'macro toolworks', 'sikuli', 'crossmacro', 'xpadder', '198macros', 'zenithmacros',
    'recoilscript', 'bhopscript', 'clickey', 'autotyper'
)
$ToolRegex = '(?i)(' + (($ToolNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
$StrongTools = '(?i)(autohotkey|autoit3|tinytask|autoclicker|gsautoclicker|opautoclicker|jitbit|macrorecorder|pulover|rapidclicker|fastclicker|clickbot|jitterclick|ghostmouse|keymousego|norecoil|antirecoil|rapidfire|dragclick|autofire|speedautoclicker|murgee|macrogamer|xpadder)'
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
    @{ Name = 'Logitech'; Vid = '046D'; Proc = 'lghub|lghub_agent|lghub_updater|lcore|lgs|logioptionsplus|logioptionsplus_agent|setpoint'; Soft = 'Logitech G HUB|Logitech Gaming Software|Logitech Options|Logi Options|SetPoint'
       Paths = @('%LOCALAPPDATA%\LGHUB', '%PROGRAMFILES%\LGHUB', '%LOCALAPPDATA%\Logitech\Logitech Gaming Software', '%APPDATA%\Logitech\Logitech Gaming Software', '%LOCALAPPDATA%\Logi\LogiOptionsPlus', '%PROGRAMDATA%\LGHUBData\applications', '%PROGRAMDATA%\LGHUB', '%APPDATA%\LGHUB_BKP', '%APPDATA%\LGHUB', '%APPDATA%\Logitech\SetPoint', '%LOCALAPPDATA%\Logitech') }
    @{ Name = 'Razer'; Vid = '1532'; Proc = 'razer synapse|razercentralservice|razersynapse|rzsynapse|razer central|razerstats|razercortex|razerappengine'; Soft = 'Razer Synapse|Razer Central|Razer Cortex'
       Paths = @('%LOCALAPPDATA%\Razer\Synapse3\Log', '%PROGRAMDATA%\Razer\Synapse3\Accounts', '%APPDATA%\Razer', '%LOCALAPPDATA%\Razer', '%PROGRAMDATA%\Razer', '%PROGRAMFILES(X86)%\Razer', '%APPDATA%\Razer\Synapse3', '%LOCALAPPDATA%\Razer\Synapse3', '%PROGRAMDATA%\Razer\Synapse3', '%LOCALAPPDATA%\Razer\RazerAppEngine\User Data', '%APPDATA%\Razer\Razer Central', '%LOCALAPPDATA%\Razer\Razer Central', '%PROGRAMDATA%\Razer\Razer Central') }
    @{ Name = 'SteelSeries'; Vid = '1038'; Proc = 'steelseriesgg|steelseriesengine|steelseriesgghelper'; Soft = 'SteelSeries GG|SteelSeries Engine'
       Paths = @('%PROGRAMDATA%\SteelSeries', '%LOCALAPPDATA%\SteelSeries', '%APPDATA%\steelseries-engine-3-client', '%LOCALAPPDATA%\steelseries-engine-3-client', '%APPDATA%\SteelSeries\GG', '%APPDATA%\SteelSeries\SteelSeries GG', '%APPDATA%\SteelSeries') }
    @{ Name = 'Corsair'; Vid = '1B1C'; Proc = 'icue|corsair'; Soft = 'iCUE|Corsair'
       Paths = @('%APPDATA%\Corsair', '%LOCALAPPDATA%\Corsair', '%PROGRAMDATA%\Corsair', '%APPDATA%\Corsair\CUE5', '%APPDATA%\Corsair\CUE4', '%APPDATA%\Corsair\CUE') }
    @{ Name = 'ASUS ROG'; Vid = '0B05'; Proc = 'armourycrate|armourysocketserver|asusappservice|rog armoury|asuscertservice|lightingservice'; Soft = 'Armoury Crate|ROG Armoury|ASUS'
       Paths = @('%USERPROFILE%\Documents\ASUS\ROG\ROG Armoury\common', '%LOCALAPPDATA%\ASUS', '%PROGRAMDATA%\ASUS', '%PROGRAMFILES%\ASUS\ARMOURY CRATE Service', '%LOCALAPPDATA%\ASUS\ArmouryCrate', '%PROGRAMDATA%\ASUS\ArmouryCrate') }
    @{ Name = 'ROCCAT'; Vid = '1E7D'; Proc = 'roccat|swarm'; Soft = 'ROCCAT Swarm'
       Paths = @('%APPDATA%\ROCCAT\SWARM\macro', '%APPDATA%\ROCCAT', '%APPDATA%\ROCCAT\ROCCAT Swarm', '%APPDATA%\ROCCAT\SWARM', '%APPDATA%\ROCCAT\SWARM\preset_macro', '%APPDATA%\ROCCAT\ROCCAT Connect') }
    @{ Name = 'Bloody/A4Tech'; Vid = '09DA'; Proc = 'bloody7|bloody|a4tech'; Soft = 'Bloody|A4Tech'
       Paths = @('%PROGRAMFILES(X86)%\Bloody7\Bloody7\Data\Mouse\English\ScriptsMacros\GunLib', '%PROGRAMFILES(X86)%\Bloody7', '%PROGRAMFILES%\Bloody7', '%APPDATA%\Bloody7', '%APPDATA%\Bloody', '%LOCALAPPDATA%\Bloody', '%PROGRAMDATA%\Bloody') }
    @{ Name = 'Glorious'; Vid = '258A'; Proc = 'gloriouscore|glorious'; Soft = 'Glorious Core|Glorious'
       Paths = @('%APPDATA%\BY-COMBO2', '%APPDATA%\BYCOMBO-2', '%APPDATA%\Glorious Core', '%LOCALAPPDATA%\Glorious Core', '%APPDATA%\glorious-core-app', '%LOCALAPPDATA%\GloriousCore', '%LOCALAPPDATA%\Glorious', '%APPDATA%\Glorious', '%APPDATA%\BYCOMBO-2\Mac', '%LOCALAPPDATA%\BY-COMBO', '%LOCALAPPDATA%\BYCOMBO-2') }
    @{ Name = 'Redragon'; Vid = '04D9'; Proc = 'redragon|gaming mouse'; Soft = 'Redragon|Gaming Mouse'
       Paths = @('%USERPROFILE%\Documents\M* Gaming Mouse\MacroDB', '%USERPROFILE%\Documents\Redragon*', '%PROGRAMFILES(X86)%\Redragon*', '%PROGRAMFILES%\Redragon*', '%APPDATA%\Redragon*', '%LOCALAPPDATA%\Redragon*', '%APPDATA%\REDRAGON\GamingMouse') }
    @{ Name = 'Cooler Master'; Vid = '2516'; Proc = 'masterplus|coolermaster'; Soft = 'MasterPlus|Cooler Master'
       Paths = @('%LOCALAPPDATA%\CoolerMaster', '%APPDATA%\CoolerMaster', '%PROGRAMDATA%\CoolerMaster', '%PROGRAMFILES(X86)%\CoolerMaster\MasterPlus') }
    @{ Name = 'HyperX'; Vid = '03F0'; Proc = 'ngenuity|hyperx'; Soft = 'NGENUITY|HyperX'
       Paths = @('%LOCALAPPDATA%\HyperX', '%APPDATA%\HyperX', '%PROGRAMDATA%\HyperX', '%APPDATA%\HyperX\NGENUITY', '%LOCALAPPDATA%\Packages\33C30B79.HyperXNGenuity_*') }
    @{ Name = 'Attack Shark/VXE'; Vid = '3554'; Proc = 'attackshark|vxe'; Soft = 'Attack Shark|VXE'
       Paths = @('%APPDATA%\AttackShark*', '%LOCALAPPDATA%\AttackShark*', '%PROGRAMDATA%\AttackShark') }
    @{ Name = 'Krom/Ayax/MotoSpeed'; Vid = ''; Proc = 'krom|ayax|motospeed'; Soft = 'KROM|AYAX|MotoSpeed'
       Paths = @('%LOCALAPPDATA%\VirtualStore\Program Files (x86)\KROM KOLT\Config', '%PROGRAMFILES%\AYAX GamingMouse', '%PROGRAMFILES(X86)%\MotoSpeed Gaming Mouse\V60\modules', '%PROGRAMFILES(X86)%\MotoSpeed Gaming Mouse', '%PROGRAMFILES(X86)%\KROM KOLT') }
)

$Vendors += @{ Name = 'X-Mouse Button Control'; Vid = ''; Proc = 'xmousebuttoncontrol'; Soft = 'X-Mouse Button Control'; Paths = @('%APPDATA%\Highresolution Enterprises\XMouseButtonControl', '%PROGRAMFILES%\Highresolution Enterprises\X-Mouse Button Control') }
$Vendors += @{ Name = 'reWASD'; Vid = ''; Proc = 'rewasd'; Soft = 'reWASD'; Paths = @('%APPDATA%\reWASD', '%PROGRAMDATA%\Disc Soft Ltd\reWASD', '%LOCALAPPDATA%\reWASD', '%PROGRAMDATA%\Disc Soft\reWASD') }
$Vendors += @{ Name = 'Wooting'; Vid = '31E3'; Proc = 'wootility|wooting'; Soft = 'Wootility|Wooting'; Paths = @('%APPDATA%\wootility*', '%APPDATA%\Wootility*', '%LOCALAPPDATA%\Wootility*', '%LOCALAPPDATA%\wootility*') }
$Vendors += @{ Name = 'Ducky/Keychron/Akko'; Vid = ''; Proc = 'ducky|keychron|akko|ajazz'; Soft = 'Ducky|Keychron|Akko|Ajazz'; Paths = @('%APPDATA%\Ducky*', '%APPDATA%\Keychron*', '%APPDATA%\Akko*', '%APPDATA%\Ajazz*', '%LOCALAPPDATA%\Ducky*', '%LOCALAPPDATA%\Akko*', '%LOCALAPPDATA%\BYCOMBO-2\Mac', '%APPDATA%\BYCOMBO-2\Mac') }
$ExtraVendors = @(
    @{ Name = 'MSI'; Vid = ''; Proc = 'dragoncenter|msicenter'; Soft = 'MSI Dragon Center|MSI Center'
       Paths = @('%APPDATA%\MSI\Dragon Center', '%APPDATA%\MSI\MSI Center') }
    @{ Name = 'Pulsar'; Vid = ''; Proc = 'pulsar'; Soft = 'Pulsar'
       Paths = @('%APPDATA%\Pulsar') }
    @{ Name = 'Finalmouse'; Vid = '373B'; Proc = 'finalmouse'; Soft = 'Finalmouse'
       Paths = @('%APPDATA%\Finalmouse') }
    @{ Name = 'ZOWIE'; Vid = ''; Proc = 'zowie'; Soft = 'ZOWIE'
       Paths = @('%APPDATA%\ZOWIE') }
    @{ Name = 'Endgame Gear'; Vid = ''; Proc = 'endgamegear'; Soft = 'Endgame Gear'
       Paths = @('%APPDATA%\Endgame Gear') }
    @{ Name = 'Alienware'; Vid = ''; Proc = 'awcc|alienware'; Soft = 'Alienware Command Center'
       Paths = @('%PROGRAMDATA%\Alienware\AlienWare Command Center', '%PROGRAMDATA%\Alienware\AWCCService') }
    @{ Name = 'Kensington'; Vid = ''; Proc = 'kensington'; Soft = 'Kensington Works'
       Paths = @('%APPDATA%\Kensington\KensingtonWorks') }
    @{ Name = 'Cougar'; Vid = ''; Proc = 'cougar'; Soft = 'Cougar UIX'
       Paths = @('%APPDATA%\Cougar\UIX') }
    @{ Name = 'Xenon200'; Vid = ''; Proc = 'xenon200'; Soft = 'Xenon200'
       Paths = @('%PROGRAMFILES(X86)%\Xenon200') }
    @{ Name = 'T16/BY-COMBO'; Vid = ''; Proc = 'bycombo|by-combo'; Soft = 'BY-COMBO|BYCOMBO'
       Paths = @('%LOCALAPPDATA%\BY-COMBO', '%APPDATA%\BYCOMBO-2', '%LOCALAPPDATA%\BYCOMBO-2\Mac') }
    @{ Name = 'Marvo'; Vid = ''; Proc = 'marvo'; Soft = 'Marvo'
       Paths = @('%LOCALAPPDATA%\BY-8801-GM917-v108') }
    @{ Name = 'Blackweb'; Vid = ''; Proc = 'blackweb'; Soft = 'Blackweb'
       Paths = @('%SystemDrive%\Blackweb Gaming AP\config') }
    @{ Name = 'SPC Gear'; Vid = ''; Proc = 'spcgear'; Soft = 'SPC Gear'
       Paths = @('%PROGRAMFILES(X86)%\SPC Gear') }
    @{ Name = 'Marsgaming'; Vid = ''; Proc = 'mmgx|marsgaming'; Soft = 'MARSGAMING|MMGX'
       Paths = @('%PROGRAMFILES(X86)%\MARSGAMING\MMGX') }
    @{ Name = 'Fantech'; Vid = ''; Proc = 'fantech'; Soft = 'Fantech'
       Paths = @('%PROGRAMFILES(X86)%\FANTECH VX7 Gaming Mouse') }
    @{ Name = 'LAMZU'; Vid = ''; Proc = 'lamzu'; Soft = 'LAMZU'
       Paths = @('%LOCALAPPDATA%\LAMZU') }
    @{ Name = 'Pwnage'; Vid = ''; Proc = 'pwnage'; Soft = 'Pwnage'
       Paths = @('%LOCALAPPDATA%\Pwnage') }
    @{ Name = 'VGN/ATK Hub'; Vid = ''; Proc = 'atkhub|vgnhub'; Soft = 'VGN Hub|ATK Hub'
       Paths = @('%APPDATA%\ATK Hub', '%LOCALAPPDATA%\VGN Hub') }
    @{ Name = 'Darmoshark'; Vid = ''; Proc = 'darmoshark'; Soft = 'Darmoshark'
       Paths = @('%LOCALAPPDATA%\Darmoshark') }
    @{ Name = 'WLmouse'; Vid = ''; Proc = 'wlmouse'; Soft = 'WLmouse'
       Paths = @('%APPDATA%\WLmouse') }
    @{ Name = 'Machenike'; Vid = ''; Proc = 'machenike'; Soft = 'Machenike'
       Paths = @('%APPDATA%\Machenike') }
    @{ Name = 'Delux'; Vid = ''; Proc = 'delux'; Soft = 'Delux'
       Paths = @('%LOCALAPPDATA%\Delux') }
    @{ Name = 'Mad Catz'; Vid = ''; Proc = 'madcatz'; Soft = 'Mad Catz'
       Paths = @('%PUBLIC%\Documents\Mad Catz') }
    @{ Name = 'Swiftpoint'; Vid = ''; Proc = 'swiftpoint'; Soft = 'Swiftpoint'
       Paths = @('%LOCALAPPDATA%\Swiftpoint') }
    @{ Name = 'UtechSmart'; Vid = ''; Proc = 'utechsmart'; Soft = 'UtechSmart'
       Paths = @('%APPDATA%\UtechSmart') }
    @{ Name = 'G-Wolves'; Vid = ''; Proc = 'gwolves|g-wolves'; Soft = 'G-Wolves'; Paths = @() }
    @{ Name = 'Zaopin'; Vid = ''; Proc = 'zaopin'; Soft = 'Zaopin'; Paths = @() }
    @{ Name = 'Waizowl'; Vid = ''; Proc = 'waizowl'; Soft = 'Waizowl'; Paths = @() }
    @{ Name = 'Rapoo'; Vid = ''; Proc = 'rapoo'; Soft = 'Rapoo'; Paths = @() }
    @{ Name = 'HAVIT'; Vid = ''; Proc = 'havit'; Soft = 'HAVIT'; Paths = @() }
    @{ Name = 'Zelotes'; Vid = ''; Proc = 'zelotes'; Soft = 'Zelotes'; Paths = @() }
    @{ Name = 'Mini Mouse Macro'; Vid = ''; Proc = 'minimousemacro'; Soft = 'Mini Mouse Macro'
       Paths = @('%APPDATA%\MiniMouseMacro') }
    @{ Name = 'MacroGamer'; Vid = ''; Proc = 'macrogamer'; Soft = 'MacroGamer'
       Paths = @('%APPDATA%\MacroGamer') }
    @{ Name = 'OP AutoClicker'; Vid = ''; Proc = 'opautoclicker'; Soft = 'OP Auto Clicker|OPAutoClicker'
       Paths = @('%APPDATA%\OPAutoClicker') }
    @{ Name = 'GS Auto Clicker'; Vid = ''; Proc = 'gsautoclicker'; Soft = 'GS Auto Clicker|GSAutoClicker'
       Paths = @('%APPDATA%\GSAutoClicker') }
    @{ Name = 'SpeedAutoClicker'; Vid = ''; Proc = 'speedautoclicker'; Soft = 'SpeedAutoClicker|Speed Auto Clicker'
       Paths = @('%APPDATA%\SpeedAutoClicker') }
    @{ Name = 'TinyTask'; Vid = ''; Proc = 'tinytask'; Soft = 'TinyTask'
       Paths = @('%APPDATA%\TinyTask') }
    @{ Name = 'Jitbit Macro Recorder'; Vid = ''; Proc = 'macrorecorder'; Soft = 'Jitbit'
       Paths = @('%APPDATA%\Jitbit\MacroRecorder') }
    @{ Name = 'Pulover Macro Creator'; Vid = ''; Proc = 'macrocreator'; Soft = 'Pulover'
       Paths = @('%APPDATA%\MacroCreator') }
    @{ Name = 'Murgee Auto Clicker'; Vid = ''; Proc = 'murgee'; Soft = 'Murgee'
       Paths = @('%APPDATA%\Murgee\Auto Clicker') }
    @{ Name = 'PTFB Pro'; Vid = ''; Proc = 'ptfbpro'; Soft = 'PTFB Pro'
       Paths = @('%PROGRAMDATA%\Technology Lighthouse\PTFB Pro') }
    @{ Name = 'GhostMouse'; Vid = ''; Proc = 'ghostmouse'; Soft = 'GhostMouse'
       Paths = @('%APPDATA%\GhostMouse') }
    @{ Name = 'DS4Windows'; Vid = ''; Proc = 'ds4windows'; Soft = 'DS4Windows'
       Paths = @('%APPDATA%\DS4Windows\Profiles') }
    @{ Name = 'InputMapper'; Vid = ''; Proc = 'inputmapper'; Soft = 'InputMapper'
       Paths = @('%APPDATA%\InputMapper') }
    @{ Name = 'TGMacro'; Vid = ''; Proc = 'tgmacro'; Soft = 'TGMacro'
       Paths = @('%APPDATA%\TGMacro') }
    @{ Name = 'Macro Toolworks'; Vid = ''; Proc = 'macrotoolworks'; Soft = 'Macro Toolworks'
       Paths = @('%APPDATA%\MacroToolworks') }
    @{ Name = 'UCR'; Vid = ''; Proc = 'universalcontrolremapper'; Soft = 'Universal Control Remapper'
       Paths = @('%APPDATA%\UCR') }
    @{ Name = 'Perfect Automation'; Vid = ''; Proc = 'perfectautomation'; Soft = 'Perfect Automation'
       Paths = @('%APPDATA%\Perfect Automation') }
    @{ Name = 'Auto Click Typer'; Vid = ''; Proc = 'autoclicktyper'; Soft = 'Auto Click Typer'
       Paths = @('%APPDATA%\AutoClickTyper') }
    @{ Name = 'Free Mouse Auto Clicker'; Vid = ''; Proc = 'freemouseautoclicker'; Soft = 'Free Mouse Auto Clicker'
       Paths = @('%APPDATA%\Free Mouse Auto Clicker') }
    @{ Name = 'Auto Keyboard Presser'; Vid = ''; Proc = 'autokeyboardpresser'; Soft = 'Auto Keyboard Presser'
       Paths = @('%APPDATA%\Auto Keyboard Presser') }
    @{ Name = 'Easy Macro Recorder'; Vid = ''; Proc = 'easymacrorecorder'; Soft = 'Easy Macro Recorder'
       Paths = @('%APPDATA%\Easy Macro Recorder') }
    @{ Name = 'VIA Keyboard Config'; Vid = ''; Proc = 'viakeyboard'; Soft = 'VIA Keyboard'
       Paths = @('%APPDATA%\VIA') }
    @{ Name = 'JoyToKey'; Vid = ''; Proc = 'joytokey'; Soft = 'JoyToKey'
       Paths = @('%USERPROFILE%\Documents\JoyToKey') }
    @{ Name = 'AntiMicroX'; Vid = ''; Proc = 'antimicrox|antimicro'; Soft = 'AntiMicro'
       Paths = @('%LOCALAPPDATA%\antimicrox') }
)
$Vendors += $ExtraVendors
$MarkerRegex = '(?i)("macros?"|macroData|macroManager|<macro|\[macro|macro=|"keyAction"|"actions"\s*:|<action|<delay|"assignments"|RecMouseClick|MemberFuncSlot|sequence|mouse ?click|left ?click|right ?click|"mouse[A-Za-z]*button")'
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
    '.cs'   = @{ Words = 'SendInput|mouse_event|SetCursorPos|keybd_event|InputSimulator|SendKeys|GetAsyncKeyState'; Need = 'SendInput|mouse_event|SetCursorPos|InputSimulator'; Min = 2 }
    '.cpp'  = @{ Words = 'SendInput|mouse_event|SetCursorPos|keybd_event|INPUT_MOUSE|GetAsyncKeyState'; Need = 'SendInput|mouse_event|SetCursorPos'; Min = 2 }
    '.c'    = @{ Words = 'SendInput|mouse_event|SetCursorPos|keybd_event|INPUT_MOUSE|GetAsyncKeyState'; Need = 'SendInput|mouse_event|SetCursorPos'; Min = 2 }
    '.java' = @{ Words = 'mousePress|mouseRelease|keyPress|java\.awt\.Robot|Robot'; Need = 'mousePress|mouseRelease|java\\.awt\\.Robot'; Min = 2 }
    '.go'   = @{ Words = 'robotgo|MouseClick|MouseToggle|KeyTap'; Need = 'robotgo'; Min = 1 }
    '.rs'   = @{ Words = 'enigo|rdev|SendInput|mouse_event'; Need = 'enigo|rdev|SendInput|mouse_event'; Min = 1 }
    '.sh'   = @{ Words = 'xdotool|ydotool|xte|nircmd|cliclick'; Need = 'xdotool|ydotool|xte|nircmd|cliclick'; Min = 1 }
    '.ts'   = @{ Words = 'robotjs|nut-tree|iohook|keyTap|mouseClick'; Need = 'robotjs|nut-tree|iohook'; Min = 1 }
    '.mjs'  = @{ Words = 'robotjs|nut-tree|iohook|keyTap|mouseClick'; Need = 'robotjs|nut-tree|iohook'; Min = 1 }
    '.bat'  = @{ Words = 'nircmd|cliclick|sendkeys|SendInput'; Need = 'nircmd|cliclick|SendInput'; Min = 1 }
    '.cmd'  = @{ Words = 'nircmd|cliclick|sendkeys|SendInput'; Need = 'nircmd|cliclick|SendInput'; Min = 1 }
}
$BinaryMacroExt = '.mcr', '.amc2', '.kbs', '.pmc', '.tcs', '.rxrec', '.atmx', '.xnr', '.kmmacros', '.pr0', '.rewasd', '.tkm', '.mmmac', '.pam', '.fac', '.akp', '.emr', '.rms'

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

function Get-UsbProduct {
    param([string]$VidHex, [string]$ProdHex)
    $out = @{ Product = ''; Maker = '' }
    foreach ($k in @(Get-ChildItem ('HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_{0}&PID_{1}' -f $VidHex, $ProdHex))) {
        $id = 'USB\VID_{0}&PID_{1}\{2}' -f $VidHex, $ProdHex, $k.PSChildName
        $bus = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc').Data
        $mk = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Manufacturer').Data
        if ($mk -and -not $out.Maker) { $out.Maker = [string]$mk }
        if ($bus) { $out.Product = [string]$bus; break }
    }
    $out
}

$VendorNameRx = [ordered]@{
    'Redragon' = 'redragon'; 'Logitech' = 'logitech'; 'Razer' = 'razer'; 'SteelSeries' = 'steelseries'; 'Corsair' = 'corsair'
    'ASUS ROG' = 'asus|rog '; 'ROCCAT' = 'roccat'; 'Bloody/A4Tech' = 'bloody|a4tech'; 'Glorious' = 'glorious'
    'Cooler Master' = 'cooler ?master'; 'HyperX' = 'hyperx'; 'Attack Shark/VXE' = 'attack ?shark|vxe'
    'Zowie/BenQ' = 'zowie|benq'; 'Finalmouse' = 'finalmouse'; 'Pulsar' = 'pulsar'; 'Lamzu' = 'lamzu'; 'Endgame Gear' = 'endgame'
    'Fantech' = 'fantech'; 'Havit' = 'havit'; 'Motospeed' = 'motospeed'; 'Marvo' = 'marvo'; 'Ajazz' = 'ajazz'; 'Rapoo' = 'rapoo'
}

function Get-VendorGuess {
    param([string]$VidHex, [string]$Text)
    foreach ($n in $VendorNameRx.Keys) { if ($Text -match ('(?i)' + $VendorNameRx[$n])) { return $n } }
    if ($VidHex -and $VidMap.ContainsKey($VidHex) -and $OemVids -notcontains $VidHex) { return ($VidMap[$VidHex] + ' (by VID, chip vendor)') }
    'unknown vendor'
}

$MicroVids = @{ '2341' = 'Arduino'; '2A03' = 'Arduino'; '16C0' = 'Teensy / V-USB'; '2E8A' = 'Raspberry Pi Pico'; '1B4F' = 'SparkFun'; '239A' = 'Adafruit'; '16D0' = 'Digispark / MCS'; '2886' = 'Seeed'; '2508' = 'Cronus Zen/Max' }
$DevCut = (Get-Date).AddDays(-$DevDays)
$activeVendors = @{}
$activeText = ''

Write-Pink 'INPUT DEVICES'
$inputDev = @{}
foreach ($d in @(Get-PnpDevice -PresentOnly -Class Mouse, Keyboard, HIDClass)) {
    $iid = [string]$d.InstanceId
    $vh = ''; $ph = ''
    if ($iid -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') { $vh = $Matches[1].ToUpper(); $ph = $Matches[2].ToUpper() }
    elseif ($iid -match 'VID&[0-9A-Fa-f]{4}([0-9A-Fa-f]{4})_PID&([0-9A-Fa-f]{4})') { $vh = $Matches[1].ToUpper(); $ph = $Matches[2].ToUpper() }
    if (-not $vh) { continue }
    $key = $vh + $ph
    if (-not $inputDev.ContainsKey($key)) { $inputDev[$key] = @{ Vid = $vh; ProdId = $ph; Types = @{}; Name = [string]$d.FriendlyName } }
    if ($d.Class -eq 'Mouse') { $inputDev[$key].Types['mouse'] = 1 }
    elseif ($d.Class -eq 'Keyboard') { $inputDev[$key].Types['keyboard'] = 1 }
    else { $inputDev[$key].Types['hid'] = 1 }
}
foreach ($e0 in ($inputDev.Values | Sort-Object { $_.Vid })) {
    $usb = Get-UsbProduct $e0.Vid $e0.ProdId
    $label = if ($usb.Product) { $usb.Product } else { $e0.Name }
    $vendor = Get-VendorGuess $e0.Vid ('{0} {1} {2}' -f $usb.Product, $usb.Maker, $e0.Name)
    $kinds = @($e0.Types.Keys | Where-Object { $_ -ne 'hid' })
    $kindLabel = if ($kinds.Count -gt 0) { ($kinds -join '+') } else { 'hid' }
    $col = if ($kinds.Count -gt 0) { 'White' } else { 'Gray' }
    Write-Host ('  {0,-14}: {1} | {2} | VID {3} PID {4}' -f $kindLabel, $label, $vendor, $e0.Vid, $e0.ProdId) -ForegroundColor $col
    $activeVendors[$e0.Vid] = 1
    $activeText += ' ' + $vendor + ' ' + $label
    if ($MicroVids.ContainsKey($e0.Vid)) {
        Add-Finding 'Hardware' 'Medium' $label ('{0} board or input emulator connected as input device ({1})' -f $MicroVids[$e0.Vid], $kindLabel) ('VID {0} PID {1}' -f $e0.Vid, $e0.ProdId) $null
    }
}
if ($inputDev.Count -eq 0) { Write-Host '  None' -ForegroundColor Gray }

Write-Pink ("`nUSB DEVICE TIMELINE (last {0} days)" -f $DevDays)
$hidDescs = @{}
foreach ($hk in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID')) {
    if ($hk.PSChildName -match '^VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
        $hkey = $Matches[1] + $Matches[2]
        foreach ($hi in @(Get-ChildItem $hk.PSPath)) {
            $dd = [string](Get-ItemProperty $hi.PSPath).DeviceDesc
            if (-not $hidDescs.ContainsKey($hkey)) { $hidDescs[$hkey] = @{} }
            if ($dd -match '(?i)mouse') { $hidDescs[$hkey]['mouse'] = 1 } elseif ($dd -match '(?i)keyboard') { $hidDescs[$hkey]['keyboard'] = 1 } else { $hidDescs[$hkey]['hid'] = 1 }
        }
    }
}
$usbMiServices = @{}
foreach ($mk in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB')) {
    if ($mk.PSChildName -match '^VID_([0-9A-F]{4})&PID_([0-9A-F]{4})&MI_') {
        $mkey = $Matches[1] + $Matches[2]
        foreach ($mi in @(Get-ChildItem $mk.PSPath)) {
            if (-not $usbMiServices.ContainsKey($mkey)) { $usbMiServices[$mkey] = @() }
            $usbMiServices[$mkey] += [string](Get-ItemProperty $mi.PSPath).Service
        }
    }
}
$timeline = New-Object System.Collections.Generic.List[object]
$olderUsb = 0
foreach ($k in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB')) {
    if ($k.PSChildName -notmatch '^VID_([0-9A-F]{4})&PID_([0-9A-F]{4})$') { continue }
    $tv = $Matches[1]; $tp = $Matches[2]
    foreach ($i in @(Get-ChildItem $k.PSPath)) {
        $props = Get-ItemProperty $i.PSPath
        $svc = [string]$props.Service
        if ($svc -match '(?i)hub') { continue }
        $iid = 'USB\{0}\{1}' -f $k.PSChildName, $i.PSChildName
        $arr = (Get-PnpDeviceProperty -InstanceId $iid -KeyName 'DEVPKEY_Device_LastArrivalDate').Data
        $rem = (Get-PnpDeviceProperty -InstanceId $iid -KeyName 'DEVPKEY_Device_LastRemovalDate').Data
        $bus = [string](Get-PnpDeviceProperty -InstanceId $iid -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc').Data
        $latest = $arr
        if ($rem -and (-not $latest -or $rem -gt $latest)) { $latest = $rem }
        if (-not $latest -or $latest -lt $DevCut) { $olderUsb++; continue }
        $types = @()
        $childSvc = @($usbMiServices[$tv + $tp])
        if ($svc -match '(?i)usbstor|uaspstor' -or $childSvc -match '(?i)usbstor|uaspstor') { $types += 'storage' }
        elseif ($svc -match '(?i)bthusb') { $types += 'bluetooth' }
        else {
            if ($hidDescs.ContainsKey($tv + $tp)) { foreach ($kk in @($hidDescs[$tv + $tp].Keys)) { if ($kk -ne 'hid') { $types += $kk } } }
            if ($types.Count -eq 0 -and $hidDescs.ContainsKey($tv + $tp)) { $types += 'hid' }
            if ($childSvc -match '(?i)usbvideo') { $types += 'camera' }
            if ($childSvc -match '(?i)usbaudio') { $types += 'audio' }
            if ($types.Count -eq 0) { $types += 'other' }
        }
        $present = [bool]($arr -and (-not $rem -or $arr -gt $rem))
        $timeline.Add([pscustomobject]@{ Types = ($types -join '+'); Name = $(if ($bus) { $bus } else { $k.PSChildName }); Vid = $tv; ProdId = $tp; Arrival = $arr; Removal = $rem; Present = $present; Latest = $latest })
        $activeVendors[$tv] = 1
        $activeText += ' ' + $bus
    }
}
foreach ($x in ($timeline | Sort-Object Latest -Descending | Select-Object -First 40)) {
    $when = if ($x.Present) { 'connected {0}, still connected' -f $x.Arrival.ToString('yyyy-MM-dd HH:mm') } else { 'connected {0}, removed {1}' -f $x.Arrival.ToString('yyyy-MM-dd HH:mm'), $x.Removal.ToString('yyyy-MM-dd HH:mm') }
    $col = if ($x.Present) { 'White' } else { 'Gray' }
    Write-Host ('  {0,-15}: {1} | VID {2} PID {3}' -f $x.Types, $x.Name, $x.Vid, $x.ProdId) -ForegroundColor $col
    Write-Host ('                   {0}' -f $when) -ForegroundColor $col
    if ($MicroVids.ContainsKey($x.Vid) -and $x.Types -notmatch 'storage') {
        Add-Finding 'Hardware' 'Medium' $x.Name ('{0} board or input emulator was connected in the last {1} days' -f $MicroVids[$x.Vid], $DevDays) ('VID {0} PID {1}' -f $x.Vid, $x.ProdId) $x.Latest
    }
    if ($x.Types -match 'storage') {
        Add-Finding 'USB storage' 'Low' $x.Name ('flash drive or USB disk was connected in the last {0} days' -f $DevDays) ('VID {0} PID {1}' -f $x.Vid, $x.ProdId) $x.Latest
    }
}
if ($timeline.Count -eq 0) { Write-Host '  None' -ForegroundColor Green }
if ($olderUsb -gt 0) { Write-Host ('  Older     : {0} devices outside the window not shown' -f $olderUsb) -ForegroundColor Gray }
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
    $col = if (($v.Vid -and $activeVendors.ContainsKey($v.Vid)) -or $activeText -match [regex]::Escape(($v.Name -split '[/ ]')[0])) { 'White' } else { 'Gray' }
    Write-Host ('  {0,-14}: {1}' -f $v.Name, $instNames) -ForegroundColor $col
    if ($rn) { Write-Host ('  {0,-14}  running: {1}' -f '', $rn) -ForegroundColor $col }
}
if ($vendorShown -eq 0) { Write-Host '  None' -ForegroundColor Gray }

function Get-MacroMarkers {
    param([string]$Text)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($mk in [regex]::Matches($Text, $MarkerRegex)) {
        if ($mk.Value -ine 'sequence') { $out.Add($mk.Value) }
    }
    $low = $Text.ToLower()
    if ($low.Contains('sequence') -and $low.Contains('delay')) { $out.Add('sequence+delay') }
    if ($low.Contains('script') -and $low.Contains('delay')) { $out.Add('script+delay') }
    if ($low.Contains('macro') -and $low.Contains('delay')) { $out.Add('macro+delay') }
    if ($low.Contains('macro') -and $low.Contains('action')) { $out.Add('macro+action') }
    if ($low.Contains('::') -and $low.Contains('send')) { $out.Add('send+::') }
    if ($low.Contains('click') -and $low.Contains('sleep')) { $out.Add('click+sleep') }
    if ($low.Contains('"assignments"') -and ($low.Contains('delay') -or $low.Contains('script'))) { $out.Add('assignments+delay') }
    return $out.ToArray()
}

function Invoke-ConfigScan {
    param([string]$Base, [string]$Label)
    $files = @()
    if (Test-Path -LiteralPath $Base -PathType Leaf) { $files = @(Get-Item -LiteralPath $Base -Force) }
    else {
        $files = @(Get-ChildItem -LiteralPath $Base -Recurse -Depth 4 -File -Force | Where-Object {
            $_.Length -lt 52428800 -and $_.Extension -match '(?i)^\.(json|xml|db|ini|dat|cfg|cuecfg|cueprofile|amc2|lua|txt|log|mac|bin|sqlite|ldb|cfgx|profile|pr0|rewasd|rec|mcr|pmc|tkm|mg|dct|macro|rms|mmmac|tw|pam|act|fac|akp|emr|ahk|au3)$' -and $_.FullName -notmatch '(?i)\\(cache|gpucache|code cache|crashpad|session storage|indexeddb|dictionaries|grpcchann|crashreports|service worker)\\'
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 60)
    }
    foreach ($cf in $files) {
        if ($cfgSeen.ContainsKey($cf.FullName)) { continue }
        $cfgSeen[$cf.FullName] = 1
        $txt = Read-Head $cf.FullName 8388608
        if (-not $txt) { continue }
        $hits = @(Get-MacroMarkers $txt)
        $macroWord = [regex]::Matches($txt, '(?i)macro').Count
        if ($hits.Count -eq 0 -and $macroWord -eq 0) { continue }
        $distinct = ($hits | ForEach-Object { $_.ToLower() } | Sort-Object -Unique)
        $level = 'Low'
        if ($cf.LastWriteTime -ge $CutRecent -and $hits.Count -ge 3) { $level = 'Medium' }
        if ($cf.LastWriteTime -ge $CutDay -and $hits.Count -ge 5) { $level = 'High' }
        $detail = '{0}: {1} markers, "macro" x{2}, distinct: {3}' -f $Label, $hits.Count, $macroWord, (($distinct | Select-Object -First 6) -join ' ')
        $macroNames = @()
        foreach ($mm in [regex]::Matches($txt, '(?i)"macro[A-Za-z]*"\s*:')) {
            $seg = $txt.Substring($mm.Index, [Math]::Min(400, $txt.Length - $mm.Index))
            $nm = [regex]::Match($seg, '(?i)"(?:name|label|title)"\s*:\s*"([^"]{1,60})"')
            if ($nm.Success) { $macroNames += $nm.Groups[1].Value }
            if ($macroNames.Count -ge 12) { break }
        }
        if ($macroNames.Count -gt 0) { $detail += '; macro names: ' + (($macroNames | Select-Object -Unique -First 8) -join ', ') }
        Add-Finding 'Vendor config' $level $cf.Name $detail $cf.FullName $cf.LastWriteTime
    }
}

Open-Section 'VENDOR CONFIGS'
$cfgSeen = @{}
foreach ($v in $Vendors) {
    foreach ($pat in $v.Paths) {
        foreach ($base in @(Expand-Pattern $pat)) { Invoke-ConfigScan $base $v.Name }
    }
}
Close-Section

Open-Section 'OTHER MOUSE SOFTWARE'
$genRx = '(?i)mouse|macro|gaming ?(mouse|software|center)|redragon|bloody|a4tech|zowie|pulsar|lamzu|finalmouse|endgame|attack ?shark|vxe|fantech|havit|motospeed|marvo|rapoo|ajazz|sinowealth|by-?combo|compx|darmoshark|waizowl|yichip|keyboard|keymap|keybind|ducky|wooting|wootility|gmmk|keychron|akko|royal ?kludge|thermaltake|tt ?esports|cougar|madcatz|rewasd|joytokey'
$genRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:USERPROFILE 'Documents'))
$genFolders = 0
foreach ($gr in ($genRoots | Where-Object { $_ } | Select-Object -Unique)) {
    foreach ($dir in @(Get-ChildItem -LiteralPath $gr -Directory -Force)) {
        if ($dir.Name -notmatch $genRx) { continue }
        $genFolders++
        Write-Host ('  Folder    : {0}' -f $dir.FullName) -ForegroundColor Gray
        Invoke-ConfigScan $dir.FullName 'mouse software'
    }
}
if ($genFolders -eq 0) { Write-Host '  Folders   : none matched' -ForegroundColor Gray }
Close-Section

Open-Section 'KEYBOARD REMAPS AND MOUSE KEYS'
$scanNames = @{ 0x01 = 'Esc'; 0x0E = 'Backspace'; 0x1C = 'Enter'; 0x1D = 'Left Ctrl'; 0x2A = 'Left Shift'; 0x36 = 'Right Shift'; 0x38 = 'Left Alt'; 0x39 = 'Space'; 0x3A = 'Caps Lock'; 0x45 = 'Num Lock'; 0x46 = 'Scroll Lock'; 0x57 = 'F11'; 0x58 = 'F12'; 0xE01D = 'Right Ctrl'; 0xE038 = 'Right Alt'; 0xE05B = 'Left Win'; 0xE05C = 'Right Win'; 0xE05D = 'Menu'; 0xE052 = 'Insert'; 0xE053 = 'Delete' }
for ($fk = 0; $fk -lt 10; $fk++) { $scanNames[0x3B + $fk] = 'F' + ($fk + 1) }
$sm = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map' -ErrorAction SilentlyContinue).'Scancode Map'
if ($sm -is [byte[]] -and $sm.Length -ge 16) {
    $cnt = [BitConverter]::ToInt32($sm, 8) - 1
    $pairs = @()
    for ($mi = 0; $mi -lt $cnt; $mi++) {
        $off = 12 + 4 * $mi
        if ($off + 3 -ge $sm.Length) { break }
        $to = [int][BitConverter]::ToUInt16($sm, $off)
        $from = [int][BitConverter]::ToUInt16($sm, $off + 2)
        $fromN = if ($scanNames.ContainsKey($from)) { $scanNames[$from] } else { '0x{0:X}' -f $from }
        $toN = if ($to -eq 0) { 'disabled' } elseif ($scanNames.ContainsKey($to)) { $scanNames[$to] } else { '0x{0:X}' -f $to }
        $pairs += ('{0} acts as {1}' -f $fromN, $toN)
    }
    if ($pairs.Count -gt 0) { Add-Finding 'Keyboard' $(if ($pairs.Count -gt 3) { 'Medium' } else { 'Low' }) 'Scancode Map (system key remap)' ($pairs -join '; ') 'HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout' $null }
}
$mkFlags = (Get-ItemProperty 'HKCU:\Control Panel\Accessibility\MouseKeys' -ErrorAction SilentlyContinue).Flags
if ($mkFlags -and (([int]$mkFlags -band 1) -eq 1)) {
    Add-Finding 'Keyboard' 'Medium' 'Windows Mouse Keys is ON' 'keyboard numpad moves the cursor and presses mouse buttons' 'HKCU\Control Panel\Accessibility\MouseKeys' $null
}
$ptFile = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Keyboard Manager\default.json'
if (Test-Path -LiteralPath $ptFile) {
    $ptText = Read-Head $ptFile 1048576
    $ptN = [regex]::Matches($ptText, '"originalKeys"').Count
    if ($ptN -gt 0) { Add-Finding 'Keyboard' 'Low' 'PowerToys Keyboard Manager remaps' ('{0} remap entries' -f $ptN) $ptFile (Get-Item $ptFile).LastWriteTime }
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
    if (($dd.DriveType -eq 'Fixed' -or $dd.DriveType -eq 'Removable') -and $dd.IsReady -and ($AllDrives -or $dd.Name.TrimEnd('\') -ne $env:SystemDrive)) { $roots += $dd.RootDirectory.FullName }
}
$roots = $roots | Where-Object { $_ } | Select-Object -Unique
$scanned = 0
$selfNorm = if ($SelfPath) { $SelfPath.ToLower() } else { '' }
$FreshOnlyExt = '.js', '.cfg', '.cs', '.cpp', '.c', '.java', '.go', '.rs', '.sh', '.ts', '.mjs', '.bat', '.cmd'
function Step-Level {
    param([string]$Lvl)
    if ($Lvl -eq 'Low') { 'Medium' } elseif ($Lvl -eq 'Medium') { 'High' } else { $Lvl }
}
foreach ($f in (Get-FilesWalk -Roots $roots -Exts $Exts -Names $Names)) {
    if ($f.ToLower() -eq $selfNorm) { continue }
    $ext0 = [IO.Path]::GetExtension($f).ToLower()
    if (($ext0 -in $FreshOnlyExt) -and [IO.File]::GetLastWriteTime($f) -lt $CutRecent) { continue }
    if ($ext0 -eq '.js' -and $f -match '\\AppData\\') { continue }
    $scanned++
    $fi = Get-Item -LiteralPath $f -Force
    if (-not $fi) { continue }
    $ext = $fi.Extension.ToLower()
    $recent = $fi.LastWriteTime -ge $CutRecent
    $inStartup = ($fi.FullName.IndexOf('\Startup\', [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($fi.FullName.IndexOf('\Start Menu\', [StringComparison]::OrdinalIgnoreCase) -ge 0)
    if ($fi.Name -ieq 'interception.dll') {
        Add-Finding 'Input driver' 'Medium' $fi.Name 'Interception library (driver-level input capture and injection)' $fi.FullName $fi.LastWriteTime
        continue
    }
    if ($BinaryMacroExt -contains $ext) {
        $mfLvl = if ($recent) { 'Medium' } else { 'Low' }
        $mfDetail = 'Macro editor file format'
        if ($inStartup) { $mfLvl = Step-Level $mfLvl; $mfDetail += '; located in a startup folder' }
        Add-Finding 'Macro file' $mfLvl $fi.Name $mfDetail $fi.FullName $fi.LastWriteTime
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
    if (($ext -in $FreshOnlyExt) -and -not $recent) { continue }
    $sh = Get-ScriptHits $ext (Read-Head $fi.FullName 262144)
    if (-not $sh) { continue }
    $lvl = if ($recent) { 'Medium' } else { 'Low' }
    if ($sh.Found.Count -ge ($sh.Min + 2) -and $recent) { $lvl = 'High' }
    $scDetail = "{0} keywords: {1}" -f $sh.Found.Count, ($sh.Found -join ', ')
    if ($inStartup) { $lvl = Step-Level $lvl; $scDetail += '; located in a startup folder' }
    Add-Finding 'Script' $lvl $fi.Name $scDetail $fi.FullName $fi.LastWriteTime
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
$pfSeen = @{}
$pfTokSeen = @{}
foreach ($vp in $Vendors) {
    foreach ($pt in ($vp.Proc -split '\|')) {
        if ($pt.Length -lt 4 -or $pt -notmatch '^[A-Za-z0-9_-]+$' -or $pfTokSeen.ContainsKey($pt.ToLower())) { continue }
        $pfTokSeen[$pt.ToLower()] = 1
        foreach ($pf2 in @(Get-ChildItem 'C:\Windows\Prefetch' -Filter ($pt + '.EXE-*.pf'))) {
            if ($pf2.LastWriteTime -lt $CutRecent -or $pf2.Name -match $ToolRegex -or $pfSeen.ContainsKey($pf2.FullName)) { continue }
            $pfSeen[$pf2.FullName] = 1
            Add-Finding 'Trace' 'Low' 'Prefetch' 'mouse or keyboard vendor software was executed' $pf2.FullName $pf2.LastWriteTime
        }
    }
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

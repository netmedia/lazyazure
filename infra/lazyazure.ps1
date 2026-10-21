#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyAzure  -  lazyazure.ps1                                            ║
#  ║   The terminal UI of a project's Azure infrastructure                    ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyAzure  -  https://github.com/netmedia/lazyazure          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
LazyAzure by Netmedia: the terminal UI of a project's Azure infrastructure (infra/infra.map.json,
infra/azure-setup.ps1).

.AUTHOR
Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
Shows the environments (infra/environments/<env>.json, infra/naming.json) and the map of their
resources and connections (infra/infra.map.json), and runs the setup (dry run, check, start, remove)
with its steps, the resources' states, the log and every question in one screen. The setup does the work
(infra/azure-setup.ps1 -Ui: events in, answers out), so both behave the same; this only shows it.

Self-contained: Windows PowerShell 5.1 or PowerShell 7, no modules. Needs what the setup needs (the Azure
CLI, the GitHub CLI). A terminal with ANSI colours and box characters (Windows Terminal; the Windows
console since Windows 10).

Keys (? shows them in the UI too)
  Home   up/down environment, Tab environments <-> actions, Enter run the action,
         d dry run, c check, s start, r remove all, a add resource, x remove resource, m map, t refresh token on/off,
         ? help, q quit
  Map    up/down resource, PgUp/PgDn scroll, a add resource, x remove it, Esc back
  Run    Enter answer (empty = the value shown), left/right choose, Space pick (several), y/n,
         '<' previous question, PgUp/PgDn/Home/End scroll the log, Esc stop (asked first);
         when done: Enter or Esc back
  New    (no map yet) n new project, q quit

.PARAMETER Help
Shows the usage guide (screens, keys, commands) and exits.

.PARAMETER Environment
The environment selected at the start (prod, test, stag, dev, accp).

.PARAMETER Keys
Testing: keys to press instead of the keyboard, comma-separated (Up, Down, Left, Right, Enter, Esc, Tab,
PgUp, PgDn, Home, End, Back, Space, a single character, text:<chars>, wait:ask, wait:done, snap).
Nothing is drawn on the console; frames go to -Frames.

.PARAMETER Frames
Testing: a text file that gets the screen (without colours) at every 'snap' and at the end.

.PARAMETER Width
Testing: the screen's width (default 120).

.PARAMETER Height
Testing: the screen's height (default 36).

.PARAMETER Engine
Testing: another setup script to run instead of the map's (project.setup).

.EXAMPLE
.\infra\lazyazure.ps1

.EXAMPLE
.\infra\lazyazure.ps1 -Environment test

.NOTES
LazyAzure is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
https://github.com/netmedia/lazyazure.

.LINK
infra/LAZYAZURE.md
#>
[CmdletBinding()]
param(
    [Alias('h')]
    [switch]$Help,
    [string]$Environment,
    [string]$Keys,
    [string]$Frames,
    [int]$Width = 0,
    [int]$Height = 0,
    [string]$Engine
)

$ErrorActionPreference = 'Stop'
$infra = $PSScriptRoot
$E = [char]27

# --- Netmedia: who made it, how to use it ---------------------------------------------------------------

$kitVersion = ''
if (Test-Path (Join-Path $infra 'kit.json')) { $kitVersion = (Get-Content (Join-Path $infra 'kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version }

function Show-Author {
    $width = 64
    $hLine = [string]::new([char]0x2500, $width)
    $v = [char]0x2502
    function Row([string]$display, [string]$measure = $display, [string]$color = 'White') {
        $pad = [Math]::Max(0, $width - $measure.Length)
        $left = [Math]::Floor($pad / 2)
        Write-Host "  $v" -NoNewline -ForegroundColor Cyan
        Write-Host "$(' ' * $left)$display$(' ' * ($pad - $left))" -NoNewline -ForegroundColor $color
        Write-Host $v -ForegroundColor Cyan
    }
    $title = 'LazyAzure  -  lazyazure.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$E[1m$title$E[0m" $title 'Cyan'
    Row 'The terminal UI of a project''s Azure infrastructure' -color 'White'
    Row ''
    Row "by Netmedia$(if ($kitVersion) { "  |  LazyAzure $kitVersion" })" -color 'DarkGray'
    Row 'https://netmedia.agency  |  netmedia@netmedia.hr' -color 'DarkGray'
    Row ''
    Write-Host "  $([char]0x2570)$hLine$([char]0x256F)" -ForegroundColor Cyan
    Write-Host ''
}

function Show-Usage {
    $hr = '  ' + [string]::new([char]0x2500, 66)
    $b = { param($t) Write-Host "  $t" -ForegroundColor White }
    $d = { param($t) Write-Host "  $t" -ForegroundColor DarkGray }
    $g = { param($t) Write-Host "  $t" -ForegroundColor Green }
    $y = { param($t) Write-Host "  $t" -ForegroundColor Yellow }
    & $b 'USAGE'
    & $g '  .\infra\lazyazure.ps1  [-Environment <env>]'
    & $d '  Run from the repository root, in Windows Terminal (or the Windows console),'
    & $d '  at least 70 x 20. The work is done by infra\azure-setup.ps1 (same questions,'
    & $d '  same results); lazyazure shows it in one screen.'
    Write-Host ''
    & $b 'SCREENS'
    & $y '  Home'
    & $d '    The environments (set up or not), the actions, and the selected environment''s'
    & $d '    answers and resources with where each connects.'
    & $y '  Map'
    & $d '    Every resource in detail (role, naming, kind, Azure type, checks, Bicep'
    & $d '    parameters, cost, app settings, secrets, connections); connections, domains,'
    & $d '    GitHub, live checks, steps. Add and remove resources here.'
    & $y '  Run'
    & $d '    The steps with their progress, the resources'' states, the log, and the question'
    & $d '    at the bottom (chips for choices, toggles for several, a text field).'
    & $y '  New project'
    & $d '    When infra has no infra.map.json yet: starts the map from the catalog.'
    & $y '  Help'
    & $d '    ? on Home or Map: keys, commands, who made it.'
    Write-Host ''
    & $b 'KEYS'
    & $y '  Home'
    & $d '    Up/Down environment, Tab environments <-> actions, Enter run the action'
    & $d '    d dry run   c check   s start   r remove all   a add resource   x remove resource   m map'
    & $d '    t refresh token on/off   ? help   q quit'
    & $y '  Map'
    & $d '    Up/Down resource, PgUp/PgDn scroll, a add resource, x remove it, Esc back'
    & $y '  Run'
    & $d '    Enter answer (empty = the value shown)   Left/Right choose   Space pick (several)'
    & $d '    y/n   < or Backspace previous question (your answer filled in)   Esc stop'
    Write-Host ''
    & $b 'WHAT THE ACTIONS RUN'
    & $d '  d  .\infra\azure-setup.ps1 -DryRun -Environment <env>    nothing changes'
    & $d '  c  .\infra\azure-setup.ps1 -Check  -Environment <env>    nothing changes'
    & $d '  s  .\infra\azure-setup.ps1 -Start  -Environment <env>    each change asked first'
    & $d '  r  .\infra\azure-setup.ps1 -Remove -Environment <env>    confirmed by name (remove all)'
    & $d '  a  .\infra\azure-setup.ps1 -AddResource                  the map + main.bicep'
    & $d '  x  .\infra\azure-setup.ps1 -RemoveResource -Key <key>    the map + main.bicep'
    & $d '  n  .\infra\azure-setup.ps1 -Init                         a new project''s map'
    Write-Host ''
    & $b 'EXAMPLES'
    & $g '  # Look around (Home, then m for the map)'
    & $g '  .\infra\lazyazure.ps1'
    Write-Host ''
    & $g '  # Start on the test environment'
    & $g '  .\infra\lazyazure.ps1 -Environment test'
    Write-Host ''
    & $b 'MORE'
    & $d '  .\infra\azure-setup.ps1 -Help   every mode and option of the setup'
    & $d '  infra\LAZYAZURE.md              the map, the catalog, naming, workflows'
    Write-Host $hr -ForegroundColor Cyan
    Write-Host ''
}

if ($Help) {
    Show-Author
    Show-Usage
    exit 0
}
function Read-InfraJson([string]$Name) { return (Get-Content (Join-Path $infra $Name) -Raw -Encoding UTF8 | ConvertFrom-Json) }
# An empty instance (the kit dropped into a project) has no map yet: the New project screen makes it.
$map = $null
if (Test-Path (Join-Path $infra 'infra.map.json')) { $map = Read-InfraJson 'infra.map.json' }
$naming = Read-InfraJson 'naming.json'
if (-not $Engine) { $Engine = Join-Path $infra 'azure-setup.ps1' }
$defs = @($map.resources | Where-Object { $_ })
$harness = [bool]($Keys -or $Frames)

# --- look -------------------------------------------------------------------------------------------

# Built from their code points: the file stays ASCII, which Windows PowerShell 5.1 reads right.
function C([int]$Code) { return [string][char]$Code }
$g = @{
    h = C 0x2500; v = C 0x2502; tl = C 0x256D; tr = C 0x256E; bl = C 0x2570; br = C 0x256F; lt = C 0x251C; rt = C 0x2524; tt = C 0x252C; bt = C 0x2534
    dot = C 0x25CF; ring = C 0x25CB; diamond = C 0x25C6; check = C 0x2713; cross = C 0x2717; arrow = C 0x2192; tri = C 0x25B8; ell = C 0x2026
    mid = C 0x00B7; bar = C 0x258C; caret = C 0x203A; cursor = C 0x2581; up = C 0x2191; down = C 0x2193; dash = C 0x2013
}
$spinner = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F) | ForEach-Object { C $_ }
# SGR parameters (256 colours).
$st = @{
    text = ''; muted = '38;5;245'; faint = '38;5;240'; bold = '1'; accent = '38;5;75'; title = '1;38;5;117'; ok = '38;5;114'; warn = '38;5;221'
    err = '38;5;203'; shared = '38;5;141'; border = '38;5;239'; sel = '48;5;236'; key = '1;38;5;222'; danger = '1;38;5;203'; brand = '1;38;5;16;48;5;209'
    chip = '38;5;250;48;5;238'; chipOn = '1;38;5;16;48;5;75'; chipDanger = '1;38;5;16;48;5;203'; head = '1;38;5;153'
    # Netmedia's signature: a coral bar and name, a teal underlined link.
    brandBar = '38;5;209'; brandName = '1;38;5;117'; netmedia = '1;38;5;209'; brandLink = '4;38;5;80'
}
$colorStyles = @{ Cyan = $st.accent; Red = $st.err; Yellow = $st.warn; Green = $st.ok; DarkGray = $st.muted; Gray = $st.muted }

# A piece of a line: text and style. A line is an array of them.
# A piece with a Link is a terminal hyperlink (OSC 8: Ctrl+click in Windows Terminal); it takes no columns.
function S([string]$T, [string]$Style = '', [string]$Link = '') { return [pscustomobject]@{ T = $T; S = $Style; Link = $Link } }
# A line cut or padded to exactly $W characters; $Bg (a background) under all of it.
function Fit($Segs, [int]$W, [string]$Bg = '') {
    $out = New-Object Collections.ArrayList
    $used = 0
    foreach ($s in @($Segs)) {
        if ($null -eq $s) { continue }
        $t = $s.T
        $style = $s.S
        if ($Bg) { if ($style) { $style = "$style;$Bg" } else { $style = $Bg } }
        $room = $W - $used
        if ($room -le 0) { break }
        if ($t.Length -gt $room) { $t = $t.Substring(0, $room - 1) + $g.ell }
        [void]$out.Add((S $t $style $s.Link))
        $used += $t.Length
    }
    if ($used -lt $W) { [void]$out.Add((S (' ' * ($W - $used)) $Bg)) }
    return , $out.ToArray()
}
function To-Ansi($Segs) {
    $sb = New-Object Text.StringBuilder
    foreach ($s in $Segs) {
        if ($s.Link) { [void]$sb.Append("$E]8;;$($s.Link)$E\") }
        if ($s.S) { [void]$sb.Append("$E[0;$($s.S)m").Append($s.T).Append("$E[0m") } else { [void]$sb.Append($s.T) }
        if ($s.Link) { [void]$sb.Append("$E]8;;$E\") }
    }
    return $sb.ToString()
}
function To-Plain($Segs) { return (-join @($Segs | ForEach-Object { $_.T })) }

# Words to lines of at most $Width; leading spaces are kept on every line.
function Wrap([string]$Text, [int]$Width) {
    if ($Width -lt 8) { $Width = 8 }
    $out = New-Object Collections.Generic.List[string]
    foreach ($para in ([string]$Text).Replace("`r", '').Split("`n")) {
        $lead = $para.Length - $para.TrimStart(' ').Length
        $indent = ' ' * [Math]::Min($lead, [int]($Width / 2))
        $room = $Width - $indent.Length
        $line = ''
        foreach ($word in $para.TrimStart(' ').Split(' ')) {
            if ($line.Length -eq 0) { $cand = $word } else { $cand = "$line $word" }
            if ($cand.Length -le $room) { $line = $cand; continue }
            if ($line.Length) { $out.Add($indent + $line) }
            while ($word.Length -gt $room) { $out.Add($indent + $word.Substring(0, $room)); $word = $word.Substring($room) }
            $line = $word
        }
        $out.Add($indent + $line)
    }
    return , $out.ToArray()
}
function Pad([string]$Text, [int]$Len) { if ($Text.Length -ge $Len) { return $Text } return $Text + (' ' * ($Len - $Text.Length)) }
function Short([string]$Text, [int]$Len) { if ($Text.Length -le $Len) { return $Text } return $Text.Substring(0, [Math]::Max(1, $Len - 1)) + $g.ell }

# --- environments and the map ------------------------------------------------------------------------

function Get-Def([string]$Key) { return $defs | Where-Object { $_.key -eq $Key } | Select-Object -First 1 }
function Load-Environments {
    $list = @()
    foreach ($p in $naming.environments.PSObject.Properties) {
        $file = Join-Path $infra "environments\$($p.Name).json"
        $saved = $null
        if (Test-Path $file) { $saved = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json }
        $list += [pscustomobject]@{ Abbr = $p.Name; Full = [string]$p.Value; Saved = $saved }
    }
    return $list
}
# A name as the naming rules would make it (for an environment that isn't set up yet).
function Get-RuleName($Def, [string]$EnvAbbr) {
    $pattern = $naming.pattern
    $type = [string]$Def.type
    if ($Def.variants) { $v = $Def.variants.([string]$Def.choice.default); if ($v.pattern) { $pattern = $naming.($v.pattern); $type = [string]$v.for } }
    elseif ($Def.pattern) { $pattern = $naming.($Def.pattern); $type = [string]$Def.for }
    $n = $pattern.Replace('{prefix}', $naming.defaults.prefix).Replace('{sub}', '').Replace('{type}', $type).Replace('{env}', $EnvAbbr)
    $n = (($n -replace '-+', '-') -replace '^-|-$', '')
    if (@($naming.noHyphens) -contains $Def.type) { $n = $n.Replace('-', '') }
    return $n
}
# Where a resource's connections go (the map's "connections"), as titles.
function Get-Targets([string]$Key, $Saved) {
    $out = @()
    foreach ($c in @($map.connections | Where-Object { $_.from -eq $Key })) {
        $to = @($c.to.Split('|') | Where-Object { -not $Saved -or $Saved.names.$_ -or $_ -eq 'github' }) | Select-Object -First 1
        if (-not $to) { $to = $c.to.Split('|')[0] }
        $d = Get-Def $to
        if ($d) { $out += $d.title } else { $out += $to }
    }
    return $out
}
function Get-Title([string]$Key) {
    if ($Key -eq 'github') { return 'GitHub Actions' }
    $titles = @($Key.Split('|') | ForEach-Object { $d = Get-Def $_; if ($d) { $d.title } else { $_ } })
    return ($titles -join ' / ')
}
$stateLook = @{
    ours = @($g.dot, $st.ok, 'in place'); exists = @($g.dot, $st.accent, 'exists'); shared = @($g.diamond, $st.shared, 'shared'); new = @($g.ring, $st.warn, 'new')
    created = @($g.dot, $st.ok, 'created'); problem = @($g.cross, $st.err, 'problem'); gone = @($g.ring, $st.faint, 'removed'); unused = @($g.ring, $st.faint, 'not needed')
    saved = @($g.dot, $st.muted, 'saved'); rule = @($g.ring, $st.faint, 'by the rules'); none = @($g.ring, $st.faint, '-')
}

# --- state ---------------------------------------------------------------------------------------------

$script:envs = @(Load-Environments)
$script:envIndex = 0
for ($i = 0; $i -lt $script:envs.Count; $i++) { if ($Environment -and $script:envs[$i].Abbr -eq $Environment) { $script:envIndex = $i } }
if (-not $Environment) { for ($i = $script:envs.Count - 1; $i -ge 0; $i--) { if ($script:envs[$i].Saved) { $script:envIndex = $i } } }
$actions = @(
    [pscustomobject]@{ Key = 'd'; Mode = 'DryRun'; Label = 'Dry run'; About = 'asks every question, shows what would change; changes nothing'; Saved = $false; Danger = $false },
    [pscustomobject]@{ Key = 'c'; Mode = 'Check'; Label = 'Check'; About = 'the saved answers, no questions; changes nothing'; Saved = $true; Danger = $false },
    [pscustomobject]@{ Key = 's'; Mode = 'Start'; Label = 'Start'; About = 'creates and updates what is missing, each change asked first'; Saved = $false; Danger = $false },
    [pscustomobject]@{ Key = 'r'; Mode = 'Remove'; Label = 'Remove all'; About = 'deletes everything the setup created for the environment (shown first, confirmed by typing the resource group''s name)'; Saved = $true; Danger = $true },
    [pscustomobject]@{ Key = 'a'; Mode = 'AddResource'; Label = 'Add resource'; About = 'adds a resource from the catalog (SQL, Service Bus, a queue, a function app, another API...) to the map with its connections, and generates main.bicep'; Saved = $false; Danger = $false },
    [pscustomobject]@{ Key = 'x'; Mode = 'RemoveResource'; Label = 'Remove resource'; About = 'takes a resource out of the map with everything that refers to it (connections, settings, roles), and generates main.bicep; Azure keeps it until you delete it'; Saved = $false; Danger = $true },
    [pscustomobject]@{ Key = 'm'; Mode = 'Map'; Label = 'Map'; About = 'every resource, how it is asked, deployed, connected and checked'; Saved = $false; Danger = $false }
)
$script:actionIndex = 1
if (-not $script:envs[$script:envIndex].Saved) { $script:actionIndex = 0 }
$script:focus = 'env'
$script:screen = 'home'
if (-not $map) { $script:screen = 'new' }
$script:refreshToken = $false
$script:message = ''
$script:mapIndex = 0
$script:mapScroll = 0
$script:run = $null
$script:quit = $false
$script:tick = 0

# --- the run -------------------------------------------------------------------------------------------

function Get-StepIndex([string]$Head) {
    $steps = @($script:run.Steps)
    for ($i = 0; $i -lt $steps.Count; $i++) { if ($Head.StartsWith($steps[$i])) { return $i } }
    return -1
}
function Add-Log([string]$Kind, [string]$Prefix, [string]$PStyle, [string]$Text, [string]$Style) {
    $step = -1
    if ($Kind -eq 'head') { $step = Get-StepIndex $Text }
    [void]$script:run.Log.Add([pscustomobject]@{ Kind = $Kind; P = $Prefix; PS = $PStyle; T = $Text; S = $Style; Step = $step })
    $script:run.Version++
}

function Reload-Map {
    $script:map = Read-InfraJson 'infra.map.json'
    $script:naming = Read-InfraJson 'naming.json'
    $script:defs = @($script:map.resources)
    $script:envs = @(Load-Environments)
    $count = @(Get-MapItems).Count
    if ($script:mapIndex -ge $count) { $script:mapIndex = $count - 1 }
}

# Adding or removing a resource changes the map, not an environment.
$mapModes = @('AddResource', 'RemoveResource', 'Init')
function Start-Run([string]$Mode, [string]$Extra) {
    $env = $script:envs[$script:envIndex]
    $action = $actions | Where-Object { $_.Mode -eq $Mode }
    $label = [string]$action.Label
    if ($Mode -eq 'Init') { $label = 'New project' }
    if ($Mode -eq 'RemoveResource' -and $Extra) { $label = "Remove $Extra" }
    if ($action.Saved -and -not $env.Saved) { $script:message = "$($env.Abbr) isn't set up yet: $($action.Label) needs its saved answers (run a dry run or start first)"; return }
    $steps = @($map.steps.setup)
    if ($Mode -eq 'Remove') { $steps = @($map.steps.remove) }
    if ($mapModes -contains $Mode) { $steps = @('Resource', 'Changes', 'Generate', 'Next steps') }
    if ($Mode -eq 'RemoveResource') { $steps = @('Resource', 'Changes', 'Generate', 'Azure', 'Next steps') }
    if ($Mode -eq 'Init') { $steps = @('Project', 'Resources', 'Changes', 'Generate', 'Next steps') }
    $run = [pscustomobject]@{
        Mode = $Mode; Label = $label; Env = $env.Abbr; Full = $env.Full; Proc = $null; Out = $null; Err = $null; OutDone = $false; ErrDone = $false
        Log = (New-Object Collections.ArrayList); Version = 0; Lines = $null; LinesKey = ''; Scroll = 0; Marks = (New-Object Collections.ArrayList)
        Steps = $steps; Res = @{}; Ask = $null; Input = ''; Choice = 0; Picked = @{}; Done = $false; Summary = $null; Code = $null
        Watch = [Diagnostics.Stopwatch]::StartNew(); ConfirmStop = $false; Last = ''; Stopped = $false; Back = $script:screen
    }
    if ($mapModes -contains $Mode) { $run.Env = 'map'; $run.Full = 'infra.map.json' }
    foreach ($def in $defs) {
        if ($env.Saved -and $env.Saved.names.($def.key)) { $run.Res[$def.key] = [pscustomobject]@{ Name = [string]$env.Saved.names.($def.key); State = 'saved'; Group = [string]$env.Saved.groups.($def.key) } }
    }
    $script:run = $run
    $script:screen = 'run'

    $exe = (Get-Process -Id $PID).Path
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Engine`" -Ui -$Mode -Environment $($env.Abbr)"
    if ($script:refreshToken -and $Mode -eq 'Start') { $arguments += ' -RefreshToken' }
    if ($Mode -eq 'RemoveResource' -and $Extra) { $arguments += " -Key $Extra" }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Split-Path $infra -Parent)
    if ($mapModes -contains $Mode) { Add-Log 'line' '' '' "$($run.Label) (the map; no environment): $(Split-Path $Engine -Leaf) -$Mode" $st.muted }
    else { Add-Log 'line' '' '' "$($run.Label) of $($env.Abbr) ($($env.Full)): $(Split-Path $Engine -Leaf) -$Mode" $st.muted }
    try {
        $run.Proc = [Diagnostics.Process]::Start($psi)
        $run.Out = $run.Proc.StandardOutput.ReadLineAsync()
        $run.Err = $run.Proc.StandardError.ReadLineAsync()
    } catch {
        Add-Log 'error' "  $($g.cross) " $st.err "Can't start the setup: $($_.Exception.Message)" $st.err
        $run.Done = $true
    }
}

function Stop-Run {
    $p = $script:run.Proc
    if ($p -and -not $p.HasExited) {
        # The setup and what it started (az, gh).
        if ($env:OS -eq 'Windows_NT') { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null } else { try { $p.Kill() } catch { } }
    }
    Add-Log 'error' "  $($g.cross) " $st.err 'Stopped.' $st.err
    $script:run.Done = $true
    $script:run.Stopped = $true
    $script:run.Watch.Stop()
    $script:run.Ask = $null
}

function Send-Answer([string]$Value, [string]$Shown) {
    $run = $script:run
    $q = [string]$run.Ask.question
    try { $run.Proc.StandardInput.WriteLine($Value); $run.Proc.StandardInput.Flush() } catch { }
    if ($Value -eq '<') { Add-Log 'answer' "  $($g.up) " $st.muted 'back to the previous question' $st.muted }
    else { Add-Log 'answer' '  ? ' $st.accent "$q  $($g.caret) $Shown" $st.text; [void]$run.Marks.Add($run.Log.Count) }
    $run.Ask = $null
    $run.Input = ''
    $run.Scroll = 0
}

# One event of the setup (azure-setup.ps1 -Ui) into the log, the steps, the resources, the question.
function Read-Event([string]$Line) {
    $run = $script:run
    if (-not $Line.StartsWith('@@ui ')) { if ($Line.Trim()) { Add-Log 'line' '    ' '' $Line $st.muted }; return }
    try { $e = $Line.Substring(5) | ConvertFrom-Json } catch { Add-Log 'line' '    ' '' $Line $st.muted; return }
    switch ([string]$e.t) {
        'line' {
            $style = $st.text
            if ($e.color -and $colorStyles.ContainsKey([string]$e.color)) { $style = $colorStyles[[string]$e.color] }
            Add-Log 'line' '' '' ([string]$e.text) $style
        }
        'head' { Add-Log 'blank' '' '' '' ''; Add-Log 'head' "$($g.bar) " $st.accent ([string]$e.text) $st.head; $run.Last = '' }
        'ok' { Add-Log 'ok' "  $($g.check) " $st.ok ([string]$e.text) $st.text }
        'missing' { Add-Log 'missing' '  ! ' $st.warn ([string]$e.text) $st.warn }
        'note' {
            $t = [string]$e.text
            if ($t.StartsWith('X ')) { Add-Log 'note' "    $($g.cross) " $st.err $t.Substring(2) $st.err }
            else { Add-Log 'note' '    ' '' $t $st.muted }
            $run.Last = $t
        }
        'auto' { Add-Log 'auto' "  $($g.mid) " $st.faint "$($e.question)  $($g.caret) $($e.value)" $st.muted }
        'ask' {
            $run.Ask = $e
            $run.Input = ''
            $run.Choice = 0
            $options = @($e.options | Where-Object { $_ })
            if ($e.kind -eq 'confirm') { $options = @('Yes', 'No') }
            $run.Ask | Add-Member -NotePropertyName Choices -NotePropertyValue $options -Force
            $default = [string]$e.default
            for ($i = 0; $i -lt $options.Count; $i++) { if ($options[$i] -ieq $default -or ($e.kind -eq 'confirm' -and $options[$i].Substring(0, 1) -ieq $default)) { $run.Choice = $i } }
            # Several choices: the default ones are picked.
            $run.Picked = @{}
            if ($e.kind -eq 'multi') { foreach ($p in $default.Split(',')) { if ($p.Trim() -and $p.Trim() -ne '-') { $run.Picked[$p.Trim()] = $true } } }
            # Asked again after < : what was answered before is ready to keep or change.
            $prev = [string]$e.previous
            if ($prev) {
                if ($e.kind -eq 'multi') {
                    $run.Picked = @{}
                    foreach ($p in $prev.Split(',')) { if ($p.Trim() -and $p.Trim() -ne '-') { $run.Picked[$p.Trim()] = $true } }
                } elseif ($options.Count) {
                    for ($i = 0; $i -lt $options.Count; $i++) { if ($options[$i] -ieq $prev -or ($e.kind -eq 'confirm' -and $options[$i].Substring(0, 1) -ieq $prev.Substring(0, 1))) { $run.Choice = $i } }
                } else { $run.Input = $prev }
            }
            $run.Scroll = 0
        }
        'res' { $run.Res[[string]$e.key] = [pscustomobject]@{ Name = [string]$e.name; State = [string]$e.state; Group = [string]$e.group } }
        'cost' {
            $w = 0
            foreach ($r in @($e.rows)) { if ($r.what.Length -gt $w) { $w = $r.what.Length } }
            foreach ($r in @($e.rows)) { Add-Log 'cost' '    ' '' ("{0}  {1}" -f (Pad $r.what $w), $r.amount) $st.text }
            Add-Log 'cost' '    ' '' ($g.h * [Math]::Min(80, $w + 20)) $st.faint
            Add-Log 'cost' '    ' '' ("{0}  {1}" -f (Pad 'Total, about' $w), $e.totalText) $st.bold
        }
        'dns' {
            Add-Log 'dns' '    ' '' ([string]$e.title) $st.accent
            foreach ($zone in @($e.records | ForEach-Object { $_.zone } | Select-Object -Unique)) {
                Add-Log 'dns' '    ' '' "At the DNS host of $zone, add:" $st.accent
                foreach ($r in @($e.records | Where-Object { $_.zone -eq $zone })) {
                    $mark = "  $($g.mid) "
                    $ms = $st.muted
                    if ($r.done) { $mark = "  $($g.check) "; $ms = $st.ok }
                    Add-Log 'dns' "    $mark" $ms ("{0,-5} {1,-28} {2,-14} {3}" -f $r.type, $r.relative, $r.how, $r.value) $st.text
                }
            }
        }
        'steps' {
            $n = 0
            foreach ($item in @($e.items)) {
                $n++
                Add-Log 'step' '  ' '' "$n. $($item.title)" $st.title
                Add-Log 'step' '     ' '' "where  $($item.where)" $st.muted
                foreach ($l in @($item.what)) { Add-Log 'step' '       ' '' ([string]$l) $st.text }
            }
        }
        'summary' {
            $run.Summary = $e
            $open = @($e.open | Where-Object { $_ })
            Add-Log 'blank' '' '' '' ''
            if ($e.cancelled) { Add-Log 'end' "  $($g.ring) " $st.muted 'Cancelled, nothing was changed.' $st.bold }
            elseif ($e.added -and -not $open.Count) { Add-Log 'end' "  $($g.check) " $st.ok "$($e.added) added to the map." "1;$($st.ok)" }
            elseif ($e.removed -and $e.key) { Add-Log 'end' "  $($g.check) " $st.ok "$($e.key) removed from the map." "1;$($st.ok)" }
            elseif ($e.removed) { Add-Log 'end' "  $($g.check) " $st.ok "$($e.env) ($($e.ghEnv)): removed." $st.ok }
            elseif ($open.Count) {
                Add-Log 'end' '  ! ' $st.warn "$($e.env) ($($e.ghEnv)): $($open.Count) open" $st.warn
                foreach ($o in $open) { Add-Log 'end' "    $($g.dash) " $st.warn ([string]$o) $st.text }
            } else { Add-Log 'end' "  $($g.check) " $st.ok "$($e.env) ($($e.ghEnv)): everything is set up." "1;$($st.ok)" }
        }
        'error' { Add-Log 'error' "  $($g.cross) " $st.err ([string]$e.text) $st.err }
        'back' {
            # The setup asks the question before again: the log goes back to just after the one before it.
            $marks = $run.Marks
            $target = 0
            if ($marks.Count -ge 2) { $target = $marks[$marks.Count - 2] }
            $keep = [Math]::Max(0, $marks.Count - 1)
            if ($marks.Count -gt $keep) { $marks.RemoveRange($keep, $marks.Count - $keep) }
            if ($run.Log.Count -gt $target -and $target -gt 0) { $run.Log.RemoveRange($target, $run.Log.Count - $target) }
            elseif ($target -eq 0 -and $run.Log.Count -gt 1) { $run.Log.RemoveRange(1, $run.Log.Count - 1) }
            $run.Version++
        }
        'saved' { $script:envs = @(Load-Environments) }
    }
}

function Update-Run {
    $run = $script:run
    if (-not $run -or -not $run.Proc) { return }
    $changed = $false
    while (-not $run.OutDone -and $run.Out.IsCompleted) {
        $line = $run.Out.Result
        if ($null -eq $line) { $run.OutDone = $true; break }
        Read-Event $line
        $changed = $true
        $run.Out = $run.Proc.StandardOutput.ReadLineAsync()
    }
    while (-not $run.ErrDone -and $run.Err.IsCompleted) {
        $line = $run.Err.Result
        if ($null -eq $line) { $run.ErrDone = $true; break }
        if ($line.Trim()) { Add-Log 'error' '    ' '' $line $st.err }
        $changed = $true
        $run.Err = $run.Proc.StandardError.ReadLineAsync()
    }
    if (-not $run.Done -and $run.OutDone -and $run.ErrDone -and $run.Proc.HasExited) {
        $run.Done = $true
        $run.Watch.Stop()
        $run.Code = $run.Proc.ExitCode
        $run.Ask = $null
        if (-not $run.Summary) { Add-Log 'end' '  ! ' $st.warn "The setup ended (exit code $($run.Code))." $st.warn }
        $script:envs = @(Load-Environments)
        $changed = $true
    }
    if ($changed) { $script:dirty = $true }
}

# Each step's state from the log: pending, running, ok, open (something missing), error.
function Get-StepStates {
    $run = $script:run
    $states = @('pending') * $run.Steps.Count
    $cur = -1
    $open = $false
    foreach ($entry in $run.Log) {
        if ($entry.Kind -eq 'head' -and $entry.Step -ge 0) {
            if ($cur -ge 0 -and $states[$cur] -eq 'running') { if ($open) { $states[$cur] = 'open' } else { $states[$cur] = 'ok' } }
            $cur = $entry.Step
            $states[$cur] = 'running'
            $open = $false
        } elseif ($entry.Kind -eq 'missing') { $open = $true }
        elseif ($entry.Kind -eq 'error' -and $cur -ge 0) { $states[$cur] = 'error' }
    }
    if ($cur -ge 0 -and $states[$cur] -eq 'running' -and $run.Done) { if ($open) { $states[$cur] = 'open' } else { $states[$cur] = 'ok' } }
    return , $states
}

# --- drawing -------------------------------------------------------------------------------------------

function Border-Top([int]$W, [string]$Left, [string]$Right, [int]$Split) {
    $segs = @((S $g.tl $st.border), (S $g.h $st.border), (S ' lazyazure ' $st.brand), (S " $Left " $st.title))
    $used = 2 + 11 + $Left.Length + 2
    $rightText = " $Right "
    $fill = $W - $used - $rightText.Length - 2
    if ($fill -lt 1) { $rightText = ''; $fill = $W - $used - 1 }
    $line = ''
    for ($i = 0; $i -lt $fill; $i++) { if ($used + $i -eq $Split) { $line += $g.tt } else { $line += $g.h } }
    $segs += (S $line $st.border)
    $segs += (S $rightText $st.muted)
    $segs += (S ($g.h + $g.tr) $st.border)
    return , (Fit $segs $W)
}
function Border-Line([int]$W, [string]$Left, [string]$Mid, [string]$Right, [int]$Split, [string]$SplitChar) {
    $line = $Left
    for ($i = 1; $i -lt $W - 1; $i++) { if ($Split -gt 0 -and $i -eq $Split) { $line += $SplitChar } else { $line += $Mid } }
    $line += $Right
    return , @(S $line $st.border)
}
function Border-Bottom([int]$W, $Hints, [int]$Split) {
    $segs = @((S ($g.bl + $g.h + ' ') $st.border))
    foreach ($h in $Hints) { $segs += (S $h[0] $st.key); $segs += (S " $($h[1])  " $st.muted) }
    $len = 0
    foreach ($s in $segs) { $len += $s.T.Length }
    $rest = $W - $len - 1
    if ($rest -gt 0) {
        $line = ''
        for ($i = 0; $i -lt $rest; $i++) { if ($len + $i -eq $Split) { $line += $g.bt } else { $line += $g.h } }
        $segs += (S $line $st.border)
    }
    $segs += (S $g.br $st.border)
    return , (Fit $segs $W)
}
# Two columns between borders: left lines (width $Lw) and right lines, $Rows rows from $Top.
function Columns($Rows, [int]$W, [int]$Lw, $Left, $Right, $LeftBg) {
    $Rw = $W - $Lw - 3
    $out = @()
    for ($i = 0; $i -lt $Rows; $i++) {
        $l = $null; $r = $null; $bg = ''
        if ($i -lt $Left.Count) { $l = $Left[$i] }
        if ($i -lt $Right.Count) { $r = $Right[$i] }
        if ($LeftBg -and $LeftBg.ContainsKey($i)) { $bg = $LeftBg[$i] }
        $segs = @(S $g.v $st.border) + (Fit $l $Lw $bg) + @(S $g.v $st.border) + (Fit $r $Rw) + @(S $g.v $st.border)
        $out += , $segs
    }
    return , $out
}
function Full-Rows($Rows, [int]$W, $Lines) {
    $out = @()
    for ($i = 0; $i -lt $Rows; $i++) {
        $l = $null
        if ($i -lt $Lines.Count) { $l = $Lines[$i] }
        $out += , (@(S $g.v $st.border) + (Fit $l ($W - 2)) + @(S $g.v $st.border))
    }
    return , $out
}

function Get-EnvDetails($Env, [int]$Width) {
    $lines = New-Object Collections.ArrayList
    $s = $Env.Saved
    $head = @((S " $($Env.Abbr) " $st.chipOn), (S "  $($Env.Full)" $st.title))
    if ($s) { $head += (S "   infra/environments/$($Env.Abbr).json" $st.muted) }
    else {
        $head += (S '   not set up yet: names by the rules' $st.warn)
        # A dry run or start offers to start from another environment's answers.
        $from = @($script:envs | Where-Object { $_.Saved } | ForEach-Object { $_.Abbr })
        if ($from.Count) { $head += (S "; d or s can copy $($from -join ' or ')'s answers" $st.muted) }
    }
    [void]$lines.Add($head)
    [void]$lines.Add(@())
    if ($s) {
        $branch = [string]$s.branch
        if ($branch -eq '-') { $branch = 'manual runs only' }
        [void]$lines.Add(@((S ' subscription  ' $st.muted), (S $s.subscriptionId), (S '   region ' $st.muted), (S $s.location), (S ' / static ' $st.muted), (S $s.staticLocation)))
        [void]$lines.Add(@((S ' repository    ' $st.muted), (S $s.repo), (S "  $($g.arrow) deployed from " $st.muted), (S $branch $st.accent)))
        $doms = @($map.domains | ForEach-Object { $v = [string]$s.($_.answer); if ($v -and $v -ne '-') { "$v" } })
        if ($doms.Count) { [void]$lines.Add(@((S ' domains       ' $st.muted), (S ($doms -join "  $($g.mid)  ") $st.accent))) }
        $sizes = @()
        foreach ($d in $defs) {
            if ($d.size -and $s.($d.size.answer)) { $sizes += "$($d.title) $($s.($d.size.answer))" }
            if ($d.choice -and $s.($d.choice.answer)) { $sizes += "$($d.title) $($s.($d.choice.answer))" }
        }
        if ($sizes.Count) { [void]$lines.Add(@((S ' sizes         ' $st.muted), (S ($sizes -join "  $($g.mid)  ")))) }
        [void]$lines.Add(@())
    }
    [void]$lines.Add(@((S ' RESOURCES ' $st.title), (S "$($g.mid) $($defs.Count) in infra.map.json" $st.muted)))
    $nameW = 0
    foreach ($d in $defs) { if ($d.title.Length -gt $nameW) { $nameW = $d.title.Length } }
    $nameW = [Math]::Min($nameW + 2, 30)
    foreach ($d in $defs) {
        $name = ''
        $look = $stateLook.rule
        if ($s) {
            $name = [string]$s.names.($d.key)
            $look = $stateLook.saved
            if (-not $name -and ($d.optional -or $d.when)) { $look = $stateLook.none; $name = 'not used here' }
            elseif (-not $name) { $look = $stateLook.new; $name = "new: a dry run or start names it in $($Env.Abbr)" }
            elseif ($s.groups -and $s.groups.($d.key)) { $look = $stateLook.shared; $name += "  (from $($s.groups.($d.key)))" }
        } else {
            $name = Get-RuleName $d $Env.Abbr
            # Asked only for some answers ("when"): not there with the defaults.
            if ($d.when) {
                $off = $false
                foreach ($p in $d.when.PSObject.Properties) {
                    foreach ($owner in $defs) { if ($owner.choice -and $owner.choice.answer -eq $p.Name -and [string]$owner.choice.default -ne [string]$p.Value) { $off = $true } }
                }
                if ($off) { $look = $stateLook.none; $name = 'only when ' + (@($d.when.PSObject.Properties | ForEach-Object { "$($_.Name) = $($_.Value)" }) -join ', ') }
            }
        }
        $nameStyle = $st.text
        if (-not $s) { $nameStyle = $st.muted }
        # Its tag: the environment's answer to its choice (shared), or when it exists (only if separate).
        $tag = ""
        if ($d.choice -and $s -and $s.($d.choice.answer)) { $tag = [string]$s.($d.choice.answer) }
        elseif ($d.tag) { $tag = [string]$d.tag }
        elseif ($d.when) { $tag = "only if " + ((@($d.when.PSObject.Properties | ForEach-Object { [string]$_.Value })) -join ", ") }
        elseif ($d.choice) { $tag = (@($d.choice.options) -join "/") }
        $row = @((S " $($look[0]) " $look[1]), (S (Pad (Short $d.title ($nameW - 2)) $nameW) $st.bold), (S $name $nameStyle))
        if ($tag) { $row += (S "  $tag" $st.accent) }
        $row += (S "  $($d.type)" $st.faint)
        [void]$lines.Add($row)
        $targets = @(Get-Targets $d.key $s)
        if ($targets.Count) { [void]$lines.Add(@((S "     $($g.arrow) " $st.faint), (S ($targets -join ', ') $st.muted))) }
    }
    return , $lines
}

function Draw-Home([int]$W, [int]$H) {
    $env = $script:envs[$script:envIndex]
    $Lw = 30
    $rows = New-Object Collections.ArrayList
    $left = New-Object Collections.ArrayList
    $bg = @{}
    [void]$left.Add(@((S ' ENVIRONMENTS' $st.title)))
    for ($i = 0; $i -lt $script:envs.Count; $i++) {
        $e = $script:envs[$i]
        $mark = '  '
        if ($i -eq $script:envIndex) { $mark = "$($g.tri) " }
        $look = @($g.ring, $st.faint)
        if ($e.Saved) { $look = @($g.dot, $st.ok) }
        $abbrStyle = $st.muted
        if ($e.Saved) { $abbrStyle = $st.bold }
        if ($i -eq $script:envIndex -and $script:focus -eq 'env') { $bg[$left.Count] = $st.sel }
        [void]$left.Add(@((S " $mark" $st.accent), (S "$($look[0]) " $look[1]), (S (Pad $e.Abbr 6) $abbrStyle), (S $e.Full $st.muted)))
    }
    [void]$left.Add(@())
    [void]$left.Add(@((S ' ACTIONS' $st.title)))
    for ($i = 0; $i -lt $actions.Count; $i++) {
        $a = $actions[$i]
        $mark = '  '
        if ($i -eq $script:actionIndex) { $mark = "$($g.tri) " }
        $style = $st.text
        if ($a.Danger) { $style = $st.err }
        if ($a.Saved -and -not $env.Saved) { $style = $st.faint }
        if ($i -eq $script:actionIndex -and $script:focus -eq 'action') { $bg[$left.Count] = $st.sel }
        [void]$left.Add(@((S " $mark" $st.accent), (S $a.Key $st.key), (S "  $($a.Label)" $style)))
    }
    [void]$left.Add(@())
    $tok = 'off'
    if ($script:refreshToken) { $tok = 'on' }
    [void]$left.Add(@((S '   t' $st.key), (S '  refresh token: ' $st.muted), (S $tok $st.accent)))
    $a = $actions[$script:actionIndex]
    [void]$left.Add(@())
    foreach ($l in (Wrap $a.About ($Lw - 4))) { [void]$left.Add(@(S "   $l" $st.muted)) }
    $right = Get-EnvDetails $env ($W - $Lw - 3)
    $bodyRows = $H - 3
    if ($script:message) { $bodyRows-- }

    # Whose it is, and where help is: at the bottom of the column (links open in the browser).
    $bar = S " $($g.bar) " $st.brandBar
    $brand = @(
        @($bar, (S 'LazyAzure ' $st.brandName), (S $kitVersion $st.faint)),
        @($bar, (S 'by ' $st.faint), (S 'Netmedia' $st.netmedia 'https://netmedia.agency')),
        @($bar, (S 'https://netmedia.agency' $st.brandLink 'https://netmedia.agency')),
        @($bar, (S '? ' $st.key), (S 'help and keys' $st.muted)))
    $gap = $bodyRows - $left.Count - $brand.Count
    if ($gap -lt 1) { $gap = 1 }
    for ($i = 0; $i -lt $gap; $i++) { [void]$left.Add(@()) }
    foreach ($b in $brand) { [void]$left.Add($b) }
    [void]$rows.Add((Border-Top $W $map.project.name 'infra/infra.map.json' ($Lw + 1)))
    foreach ($r in (Columns $bodyRows $W $Lw $left $right $bg)) { [void]$rows.Add($r) }
    if ($script:message) { [void]$rows.Add((@(S $g.v $st.border) + (Fit @((S ' ! ' $st.warn), (S $script:message $st.warn)) ($W - 2)) + @(S $g.v $st.border))) }
    [void]$rows.Add((Border-Line $W $g.lt $g.h $g.rt ($Lw + 1) $g.bt))
    [void]$rows.Add((Border-Bottom $W @(@("$($g.up)$($g.down)", 'select'), @('Tab', 'list'), @('Enter', 'run'), @('d c s r', 'dry run, check, start, remove all'), @('a x', 'add, remove resource'), @('m', 'map'), @('t', 'token'), @('?', 'help'), @('q', 'quit')) 0))
    return , $rows
}

# The map screen: one entry per resource, then the connections, domains, GitHub, live checks.
function Get-MapItems {
    $items = @()
    foreach ($d in $defs) { $items += [pscustomobject]@{ Title = $d.title; Def = $d; Kind = 'resource' } }
    $items += [pscustomobject]@{ Title = 'Connections'; Def = $null; Kind = 'connections' }
    $items += [pscustomobject]@{ Title = 'Custom domains'; Def = $null; Kind = 'domains' }
    $items += [pscustomobject]@{ Title = 'GitHub'; Def = $null; Kind = 'github' }
    $items += [pscustomobject]@{ Title = 'Live checks'; Def = $null; Kind = 'live' }
    $items += [pscustomobject]@{ Title = 'Steps'; Def = $null; Kind = 'steps' }
    return $items
}
function Add-Field($Lines, [string]$Label, [string]$Value, [string]$Style, [int]$Width) {
    if (-not $Value) { return }
    $first = $true
    foreach ($l in (Wrap $Value ($Width - 17))) {
        $lab = ''
        if ($first) { $lab = $Label }
        [void]$Lines.Add(@((S (' ' + (Pad $lab 15) + ' ') $st.muted), (S $l $Style)))
        $first = $false
    }
}
function Get-MapDetails($Item, [int]$Width) {
    $lines = New-Object Collections.ArrayList
    $env = $script:envs[$script:envIndex]
    if ($Item.Kind -eq 'resource') {
        $d = $Item.Def
        [void]$lines.Add(@((S " $($d.title)" $st.title), (S "   $($d.key)" $st.faint)))
        [void]$lines.Add(@())
        Add-Field $lines 'role' $d.role $st.text $Width
        $typeAbout = $naming.types.($d.type)
        Add-Field $lines 'naming type' "$($d.type)$(if ($typeAbout) { "  ($typeAbout)" })" $st.text $Width
        $name = ''
        if ($env.Saved) { $name = [string]$env.Saved.names.($d.key) } else { $name = (Get-RuleName $d $env.Abbr) + '  (by the rules)' }
        Add-Field $lines "name in $($env.Abbr)" $name $st.accent $Width
        Add-Field $lines 'kind' "$($d.kind)  (infra/catalog/$($d.kind).bicep)" $st.accent $Width
        Add-Field $lines 'Azure type' $d.armType $st.text $Width
        $asks = @{ group = 'the resource group of the environment'; own = "lives in the environment's group (an existing one only there)"; shared = 'may also be an existing one from another group, used as it is'; workspace = "Log Analytics of $((@($d.neededBy) | ForEach-Object { Get-Title $_ }) -join ', '), when one of them is managed here"; name = 'only a name'; child = 'only a name: it lives inside another resource (a database on its server, a queue in its storage account)' }
        Add-Field $lines 'asked as' $asks[[string]$d.ask] $st.text $Width
        if ($d.target) { Add-Field $lines 'sub app name' "of $($d.targetLabel) ($($d.target))" $st.text $Width }
        if ($d.label) { Add-Field $lines 'question' $d.label $st.text $Width }
        if ($d.choice) { Add-Field $lines 'choice' "$($d.choice.label): $(@($d.choice.options) -join ', ') (default $($d.choice.default))" $st.text $Width }
        if ($d.choice -and $env.Saved -and $env.Saved.($d.choice.answer)) { Add-Field $lines "in $($env.Abbr)" ([string]$env.Saved.($d.choice.answer)) $st.accent $Width }
        if ($d.when) { Add-Field $lines 'only when' (@($d.when.PSObject.Properties | ForEach-Object { "$($_.Name) = $($_.Value)" }) -join ', ') $st.text $Width }
        if ($d.size) { Add-Field $lines 'size' "$($d.size.label): $(@($d.size.options) -join ', ') (default $($d.size.default))" $st.text $Width }
        $checks = @()
        if ($d.free) { $checks += "new name: $($d.free)" }
        if ($d.check) { $checks += "existing: $($d.check)" }
        Add-Field $lines 'checks' ($checks -join '; ') $st.text $Width
        $params = @($d.param, $d.groupParam) | Where-Object { $_ }
        if ($d.size) { $params += $d.size.param }
        Add-Field $lines 'main.bicep' ($params -join ', ') $st.accent $Width
        if ($d.cost) { Add-Field $lines 'cost' "$($d.cost.kind): $($d.cost.label)" $st.text $Width }
        if ($d.appSettings) {
            [void]$lines.Add(@())
            [void]$lines.Add(@(S ' APP SETTINGS (checked after what-if)' $st.title))
            foreach ($a in @($d.appSettings)) {
                $rule = 'set'
                if ($a.value) { $rule = "= $($a.value)" } elseif ($a.prefix) { $rule = "starts with $($a.prefix)" }
                [void]$lines.Add(@((S "   $(Pad $a.name 40) " $st.text), (S $rule $st.muted)))
            }
        }
        if ($d.secrets) {
            [void]$lines.Add(@())
            [void]$lines.Add(@(S ' SECRETS' $st.title))
            foreach ($s in @($d.secrets)) {
                $about = $s.about
                if (-not $about) { $about = $s.what }
                [void]$lines.Add(@((S "   $(Pad $s.name 22) " $st.text), (S "by $(Pad $s.by 6) " $st.accent), (S $about $st.muted)))
            }
        }
        # Its deploy: which folder of which branch is built how and published where (a generated workflow).
        if ($d.deploy) {
            $dep = $d.deploy
            [void]$lines.Add(@())
            [void]$lines.Add(@(S ' DEPLOY (GitHub Actions, generated)' $st.title))
            Add-Field $lines 'workflow' ".github/workflows/$($dep.workflow)  ($($dep.name))" $st.accent $Width
            Add-Field $lines 'source' "$($dep.source)/" $st.accent $Width
            $branches = @($script:envs | Where-Object { $_.Saved -and $_.Saved.branch -and $_.Saved.branch -ne '-' } | ForEach-Object { "$($_.Saved.branch) -> $($_.Abbr)" })
            $trigger = 'manual runs only (no environment has a deploy branch yet)'
            if ($branches.Count) { $trigger = "a push to $($branches -join ', ')" }
            if ($dep.everyBranch) { $trigger = "a push to any branch runs its tests; deploys from $(if ($branches.Count) { $branches -join ', ' } else { 'no branch yet' })" }
            Add-Field $lines 'trigger' $trigger $st.text $Width
            $paths = @("$($dep.source)/**") + @($dep.paths | Where-Object { $_ } | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.path } })
            Add-Field $lines 'paths' ($paths -join ', ') $st.muted $Width
            switch ([string]$d.kind) {
                'staticWebApp' {
                    $what = "builds in $($dep.source)/ (Node $($dep.node)), publishes $($dep.app)"
                    if ($dep.api) { $what += " + functions $($dep.api)" }
                    Add-Field $lines 'build' $what $st.text $Width
                }
                default {
                    $what = "dotnet publish $(if ($dep.project) { $dep.project } else { $dep.source }) (.NET $($dep.dotnet))"
                    if ($dep.test) { $what += "; tests first: $($dep.test.run)" }
                    Add-Field $lines 'build' $what $st.text $Width
                }
            }
            $where = 'the app of the environment the branch belongs to'
            if ($env.Saved -and $env.Saved.names.($d.key)) { $where = "in $($env.Abbr): $($env.Saved.names.($d.key))" }
            Add-Field $lines 'publishes to' $where $st.accent $Width
        }
        $out = @($map.connections | Where-Object { $_.from -eq $d.key })
        $in = @($map.connections | Where-Object { @($_.to.Split('|')) -contains $d.key })
        if ($out.Count -or $in.Count) {
            [void]$lines.Add(@())
            [void]$lines.Add(@(S ' CONNECTIONS' $st.title))
            foreach ($c in $out) { [void]$lines.Add(@((S "   $($g.arrow) " $st.accent), (S (Get-Title $c.to) $st.bold), (S "  $($c.what)" $st.text), (S "  ($($c.via))" $st.muted))) }
            foreach ($c in $in) { [void]$lines.Add(@((S "   $([string][char]0x2190) " $st.shared), (S (Get-Title $c.from) $st.bold), (S "  $($c.what)" $st.text), (S "  ($($c.via))" $st.muted))) }
        }
    } elseif ($Item.Kind -eq 'connections') {
        [void]$lines.Add(@(S ' Connections' $st.title))
        [void]$lines.Add(@(S ' How the resources work together (main.bicep wires them)' $st.muted))
        [void]$lines.Add(@())
        foreach ($c in @($map.connections)) {
            [void]$lines.Add(@((S "  $(Get-Title $c.from)" $st.bold), (S " $($g.h)$($g.h)$($g.tri) " $st.accent), (S (Get-Title $c.to) $st.bold)))
            [void]$lines.Add(@((S "      $($c.what)" $st.text), (S "  $($g.mid) $($c.via)" $st.muted)))
        }
    } elseif ($Item.Kind -eq 'domains') {
        [void]$lines.Add(@(S ' Custom domains' $st.title))
        [void]$lines.Add(@())
        foreach ($dm in @($map.domains)) {
            $v = ''
            if ($env.Saved) { $v = [string]$env.Saved.($dm.answer) }
            [void]$lines.Add(@(S "  $(Get-Title $dm.resource)" $st.bold))
            Add-Field $lines 'answer' $dm.answer $st.text $Width
            Add-Field $lines "in $($env.Abbr)" $v $st.accent $Width
            Add-Field $lines 'DNS' $dm.dns $st.text $Width
            Add-Field $lines 'prod default' $dm.prodDefault $st.muted $Width
            [void]$lines.Add(@())
        }
    } elseif ($Item.Kind -eq 'github') {
        [void]$lines.Add(@(S ' GitHub' $st.title))
        [void]$lines.Add(@())
        [void]$lines.Add(@(S '  ENVIRONMENT VARIABLES' $st.title))
        foreach ($p in $map.github.variables.PSObject.Properties) { [void]$lines.Add(@((S "   $(Pad $p.Name 26) " $st.text), (S $p.Value $st.muted))) }
        [void]$lines.Add(@())
        foreach ($t in @($map.github.tokenSecrets)) { Add-Field $lines 'token secret' "$($t.name) from $(Get-Title $t.resource)" $st.text $Width }
        foreach ($r in @($map.github.deployRoles)) { Add-Field $lines 'deploy role' "$($r.role) on $(Get-Title $r.resource)" $st.text $Width }
        Add-Field $lines 'workflows' (@($map.github.workflows) -join ', ') $st.text $Width
        Add-Field $lines 'a push' $map.github.push $st.muted $Width
    } elseif ($Item.Kind -eq 'live') {
        [void]$lines.Add(@(S ' Live checks (step 5)' $st.title))
        [void]$lines.Add(@())
        foreach ($l in @($map.live)) {
            $what = "GET $($l.path)"
            if ($l.kind -eq 'health') { $what += " = $($l.expect); version $($l.version)" } else { $what += " matches $($l.match)" }
            [void]$lines.Add(@(S "  $(Get-Title $l.resource)" $st.bold))
            Add-Field $lines 'check' $what $st.text $Width
            Add-Field $lines 'also on' $l.domain $st.text $Width
            Add-Field $lines 'deployed by' $l.workflow $st.muted $Width
            [void]$lines.Add(@())
        }
    } else {
        [void]$lines.Add(@(S ' Steps of a run' $st.title))
        [void]$lines.Add(@())
        foreach ($k in @('setup', 'remove')) {
            [void]$lines.Add(@(S "  $($k.ToUpper())" $st.title))
            foreach ($s in @($map.steps.$k)) { [void]$lines.Add(@((S "   $($g.mid) " $st.accent), (S $s))) }
            [void]$lines.Add(@())
        }
        [void]$lines.Add(@(S '  REMOVE ORDER' $st.title))
        foreach ($s in @($map.removeOrder)) { [void]$lines.Add(@((S "   $($g.mid) " $st.accent), (S $s))) }
    }
    return , $lines
}
function Draw-Map([int]$W, [int]$H) {
    $items = @(Get-MapItems)
    $Lw = 34
    $left = New-Object Collections.ArrayList
    $bg = @{}
    [void]$left.Add(@(S ' THE MAP' $st.title))
    for ($i = 0; $i -lt $items.Count; $i++) {
        if ($items[$i].Kind -eq 'connections') { [void]$left.Add(@()) }
        $mark = '  '
        if ($i -eq $script:mapIndex) { $mark = "$($g.tri) "; $bg[$left.Count] = $st.sel }
        $glyph = S '  ' ''
        if ($items[$i].Def) {
            $env = $script:envs[$script:envIndex]
            $look = $stateLook.rule
            if ($env.Saved) { if ($env.Saved.names.($items[$i].Def.key)) { $look = $stateLook.saved } else { $look = $stateLook.none } }
            $glyph = S "$($look[0]) " $look[1]
        }
        [void]$left.Add(@((S " $mark" $st.accent), $glyph, (S $items[$i].Title)))
    }
    $Rw = $W - $Lw - 3
    $details = Get-MapDetails $items[$script:mapIndex] $Rw
    $bodyRows = $H - 3
    $max = [Math]::Max(0, $details.Count - $bodyRows)
    if ($script:mapScroll -gt $max) { $script:mapScroll = $max }
    $right = @()
    for ($i = $script:mapScroll; $i -lt $details.Count; $i++) { $right += , $details[$i] }
    $rows = New-Object Collections.ArrayList
    [void]$rows.Add((Border-Top $W "$($map.project.name) $($g.mid) map" "$($script:envs[$script:envIndex].Abbr) $($g.mid) infra/infra.map.json" ($Lw + 1)))
    foreach ($r in (Columns $bodyRows $W $Lw $left $right $bg)) { [void]$rows.Add($r) }
    [void]$rows.Add((Border-Line $W $g.lt $g.h $g.rt ($Lw + 1) $g.bt))
    [void]$rows.Add((Border-Bottom $W @(@("$($g.up)$($g.down)", 'select'), @('PgUp PgDn', 'scroll'), @('a', 'add resource'), @('x', 'remove it'), @('?', 'help'), @('Esc', 'back')) 0))
    return , $rows
}

# The log as lines of the right width (cached until the log or the width changes).
function Get-LogLines([int]$Width) {
    $run = $script:run
    $key = "$($run.Version)/$Width"
    if ($run.LinesKey -eq $key) { return , $run.Lines }
    $lines = New-Object Collections.ArrayList
    foreach ($entry in $run.Log) {
        if ($entry.Kind -eq 'blank') { [void]$lines.Add(@()); continue }
        $p = [string]$entry.P
        $first = $true
        foreach ($l in (Wrap $entry.T ($Width - $p.Length - 1))) {
            if ($first) { [void]$lines.Add(@((S " $p" $entry.PS), (S $l $entry.S))) }
            else { [void]$lines.Add(@((S (' ' * ($p.Length + 1)) ''), (S $l $entry.S))) }
            $first = $false
        }
    }
    $run.Lines = $lines
    $run.LinesKey = $key
    return , $lines
}
function Draw-Run([int]$W, [int]$H) {
    $run = $script:run
    $Lw = 34
    $Rw = $W - $Lw - 3
    $spin = $spinner[$script:tick % $spinner.Count]
    $states = Get-StepStates

    # Left: steps, then resources.
    $left = New-Object Collections.ArrayList
    [void]$left.Add(@(S ' STEPS' $st.title))
    for ($i = 0; $i -lt $run.Steps.Count; $i++) {
        $look = switch ($states[$i]) {
            'running' { @($spin, $st.accent, $st.bold) }
            'ok' { @($g.check, $st.ok, $st.text) }
            'open' { @('!', $st.warn, $st.text) }
            'error' { @($g.cross, $st.err, $st.err) }
            default { @($g.mid, $st.faint, $st.muted) }
        }
        [void]$left.Add(@((S "  $($look[0]) " $look[1]), (S $run.Steps[$i] $look[2])))
    }
    [void]$left.Add(@())
    [void]$left.Add(@(S ' RESOURCES' $st.title))
    foreach ($d in $defs) {
        $r = $run.Res[$d.key]
        if (-not $r) { [void]$left.Add(@((S "  $($g.ring) " $st.faint), (S (Short $d.title ($Lw - 5)) $st.faint))); continue }
        $look = $stateLook[$r.State]
        if (-not $look) { $look = $stateLook.saved }
        [void]$left.Add(@((S "  $($look[0]) " $look[1]), (S (Pad (Short $d.title 20) 21) $st.text), (S $look[2] $look[1])))
    }

    # Bottom: the question, or what is going on.
    $prompt = New-Object Collections.ArrayList
    $hints = @()
    $ask = $run.Ask
    if ($run.ConfirmStop) {
        [void]$prompt.Add(@((S ' Stop the run? ' $st.danger), (S 'What was already changed stays.' $st.muted)))
        [void]$prompt.Add(@((S '  y ' $st.chipDanger), (S ' stop   ' $st.muted), (S '  n ' $st.chip), (S ' go on' $st.muted)))
        $hints = @(@('y', 'stop'), @('n Esc', 'go on'))
    } elseif ($ask) {
        $qStyle = $st.bold
        if ($ask.danger) { $qStyle = $st.danger }
        $q = Wrap ([string]$ask.question) ($W - 6)
        [void]$prompt.Add(@((S ' ? ' $st.accent), (S $q[0] $qStyle)))
        if ($q.Count -gt 1) { [void]$prompt.Add(@((S '   '), (S $q[1] $qStyle))) }
        if ($ask.Choices -and $ask.Choices.Count) {
            $chips = @(S '   ')
            for ($i = 0; $i -lt $ask.Choices.Count; $i++) {
                $style = $st.chip
                $text = " $($ask.Choices[$i]) "
                if ($ask.kind -eq 'multi') {
                    # Picked ones in colour, the one under the cursor marked.
                    $mark = $g.ring
                    if ($run.Picked[$ask.Choices[$i]]) { $mark = $g.check; $style = $st.chipOn }
                    $shownText = $ask.Choices[$i]
                    if ($ask.labels -and @($ask.labels).Count -gt $i -and @($ask.labels)[$i]) { $shownText = [string]@($ask.labels)[$i] }
                    $text = " $mark $shownText "
                    if ($i -eq $run.Choice) { $chips += (S $g.tri $st.key) } else { $chips += (S ' ') }
                } elseif ($i -eq $run.Choice) { $style = $st.chipOn; if ($ask.kind -eq 'confirm' -and $i -eq 0 -and ($run.Mode -eq 'Remove' -or $run.Mode -eq 'RemoveResource')) { $style = $st.chipDanger } }
                $chips += (S $text $style)
                $chips += (S ' ')
            }
            if ($ask.canBack) { $chips += (S '   ' ''); $chips += (S ' < back ' $st.chip) }
            [void]$prompt.Add($chips)
            $hints = @(@("$([string][char]0x2190)$([string][char]0x2192)", 'choose'), @('Enter', 'answer'))
            if ($ask.kind -eq 'confirm') { $hints += , @('y n', 'yes, no') }
            if ($ask.kind -eq 'multi') { $hints = @(@("$([string][char]0x2190)$([string][char]0x2192)", 'move'), @('Space', 'pick'), @('Enter', 'answer')) }
        } else {
            $value = $run.Input
            $line = @((S "   $($g.caret) " $st.accent))
            if ($value) { $line += (S $value $st.bold); $line += (S $g.cursor $st.accent) }
            else { $line += (S $g.cursor $st.accent); if ($ask.default) { $line += (S " $($ask.default)" $st.muted); $line += (S '  (Enter keeps it)' $st.faint) } }
            if ($ask.canBack) { $line += (S '     ' ''); $line += (S ' < back ' $st.chip) }
            [void]$prompt.Add($line)
            $hints = @(, @('Enter', 'answer'))
        }
        if ($ask.canBack) { $hints += , @('< Backspace', 'previous question') }
        $hints += , @('PgUp PgDn', 'scroll')
    } elseif ($run.Done) {
        $s = $run.Summary
        if ($s -and $s.added -and -not @($s.open | Where-Object { $_ }).Count) { [void]$prompt.Add(@((S " $($g.check) " $st.ok), (S "$($s.added) is in the map, main.bicep generated. A dry run asks its names and shows what it creates." $st.ok))) }
        elseif ($s -and $s.removed -and $s.key -and $s.deleted) { [void]$prompt.Add(@((S " $($g.check) " $st.ok), (S "$($s.key) is out of the map and deleted from Azure in $($s.deleted) environment(s)." $st.ok))) }
        elseif ($s -and $s.removed -and $s.key) { [void]$prompt.Add(@((S " $($g.check) " $st.ok), (S "$($s.key) is out of the map, main.bicep generated; Azure kept it." $st.ok))) }
        elseif ($s -and $s.removed) { [void]$prompt.Add(@((S " $($g.check) " $st.ok), (S "$($s.env) removed." $st.ok))) }
        elseif ($s -and $s.cancelled) { [void]$prompt.Add(@((S " $($g.ring) " $st.muted), (S 'Cancelled, nothing was changed.' $st.muted))) }
        elseif ($s -and @($s.open | Where-Object { $_ }).Count) { [void]$prompt.Add(@((S ' ! ' $st.warn), (S "$(@($s.open | Where-Object { $_ }).Count) open in $($s.env) $($g.mid) the log lists them and the next steps" $st.warn))) }
        elseif ($s) { [void]$prompt.Add(@((S " $($g.check) " $st.ok), (S "$($s.env) ($($s.ghEnv)): everything is set up." "1;$($st.ok)"))) }
        elseif ($run.Stopped) { [void]$prompt.Add(@((S " $($g.cross) " $st.err), (S 'Stopped. What was already changed stays; a check shows where it is.' $st.err))) }
        else { [void]$prompt.Add(@((S ' ! ' $st.warn), (S "The setup ended (exit code $($run.Code))." $st.warn))) }
        [void]$prompt.Add(@(S "   $($run.Label) $($g.mid) $([int]$run.Watch.Elapsed.TotalMinutes):$($run.Watch.Elapsed.Seconds.ToString('00'))" $st.muted))
        $hints = @(@('Enter Esc', 'back'), @('PgUp PgDn Home End', 'scroll'))
    } else {
        $cur = ''
        for ($i = 0; $i -lt $states.Count; $i++) { if ($states[$i] -eq 'running') { $cur = $run.Steps[$i] } }
        [void]$prompt.Add(@((S " $spin " $st.accent), (S "working $($g.mid) $cur" $st.bold)))
        if ($run.Last) { [void]$prompt.Add(@(S "   $($run.Last)" $st.muted)) }
        $hints = @(@('PgUp PgDn', 'scroll'), @('Esc', 'stop'))
    }
    $promptRows = 3

    $bodyRows = $H - 4 - $promptRows
    $logLines = Get-LogLines ($Rw - 1)
    $max = [Math]::Max(0, $logLines.Count - $bodyRows)
    if ($run.Scroll -gt $max) { $run.Scroll = $max }
    $start = $max - $run.Scroll
    $right = @()
    for ($i = $start; $i -lt [Math]::Min($logLines.Count, $start + $bodyRows); $i++) { $right += , $logLines[$i] }

    $elapsed = $run.Watch.Elapsed
    $status = "$($run.Env) $($g.mid) $($run.Full) $($g.mid) $([int]$elapsed.TotalMinutes):$($elapsed.Seconds.ToString('00'))"
    if ($run.Scroll) { $status = "$($g.up) $($run.Scroll) lines  $($g.mid)  $status" }
    $rows = New-Object Collections.ArrayList
    [void]$rows.Add((Border-Top $W "$($map.project.name) $($g.mid) $($run.Label)" $status ($Lw + 1)))
    foreach ($r in (Columns $bodyRows $W $Lw $left $right $null)) { [void]$rows.Add($r) }
    [void]$rows.Add((Border-Line $W $g.lt $g.h $g.rt ($Lw + 1) $g.bt))
    foreach ($r in (Full-Rows $promptRows $W $prompt)) { [void]$rows.Add($r) }
    [void]$rows.Add((Border-Line $W $g.lt $g.h $g.rt 0 ''))
    [void]$rows.Add((Border-Bottom $W $hints 0))
    return , $rows
}

function Draw([int]$W, [int]$H) {
    if ($W -lt 70 -or $H -lt 20) {
        $rows = @()
        for ($i = 0; $i -lt $H; $i++) { $rows += , @(S '') }
        $rows[0] = Fit @(S "lazyazure needs a window of at least 70 x 20 (now $W x $H)." $st.warn) $W
        return , $rows
    }
    switch ($script:screen) {
        'new' { return Draw-New $W $H }
        'help' { return Draw-Help $W $H }
        'map' { return Draw-Map $W $H }
        'run' { return Draw-Run $W $H }
        default { return Draw-Home $W $H }
    }
}

# Help: what this is, who made it, the keys of every screen and what each action runs.
$script:helpScroll = 0
function Draw-Help([int]$W, [int]$H) {
    $lines = New-Object Collections.ArrayList
    $add = { param($segs) [void]$lines.Add($segs) }
    [void]$lines.Add(@())
    [void]$lines.Add(@((S ' '), (S $g.bar $st.brandBar), (S 'LazyAzure ' $st.brandName), (S "$kitVersion  " $st.faint), (S 'by ' $st.faint), (S 'Netmedia' $st.netmedia 'https://netmedia.agency')))
    [void]$lines.Add(@((S ' '), (S $g.bar $st.brandBar), (S 'https://netmedia.agency' $st.brandLink 'https://netmedia.agency'), (S '  |  ' $st.faint), (S 'netmedia@netmedia.hr' $st.brandLink 'mailto:netmedia@netmedia.hr'), (S '  |  ' $st.faint), (S 'https://github.com/netmedia/lazyazure' $st.brandLink 'https://github.com/netmedia/lazyazure')))
    [void]$lines.Add(@())
    foreach ($l in (Wrap 'A project''s Azure infrastructure from one map (infra/infra.map.json): set up, checked, changed and removed environment by environment. lazyazure shows it; infra/azure-setup.ps1 does the work (the same questions and results without the UI); main.bicep is generated from the map.' ($W - 8))) { [void]$lines.Add(@(S "  $l")) }
    [void]$lines.Add(@())
    $section = {
        param([string]$Title, $Rows)
        [void]$lines.Add(@(S "  $Title" $st.title))
        foreach ($r in $Rows) { [void]$lines.Add(@((S ('    ' + (Pad $r[0] 14)) $st.key), (S $r[1] $st.text))) }
        [void]$lines.Add(@())
    }
    & $section 'HOME' @(
        @("$($g.up) $($g.down)", 'select an environment (or an action, after Tab)'),
        @('Tab', 'environments <-> actions'), @('Enter', 'run the selected action'),
        @('d', 'dry run: every question, what would change; nothing changes'),
        @('c', 'check: the saved answers, no questions; nothing changes'),
        @('s', 'start: creates and updates what is missing, each change asked first'),
        @('r', 'remove all: deletes everything the setup created for the environment (confirmed by name)'),
        @('a', 'add a resource from the catalog to the map'), @('x', 'remove a resource from the map; deleting it from Azure is asked (typed name)'), @('m', 'the map'),
        @('t', 'refresh token: puts a Static Web App''s token into GitHub again on start'),
        @('?', 'this help'), @('q', 'quit'))
    & $section 'MAP' @(
        @("$($g.up) $($g.down)", 'select a resource (or connections, domains, GitHub...)'),
        @('PgUp PgDn', 'scroll the details'), @('a', 'add a resource'), @('x', 'remove the selected resource from the map'), @('Esc', 'back'))
    & $section 'RUN' @(
        @('Enter', 'answer (empty = the value shown)'), @("$([string][char]0x2190) $([string][char]0x2192)", 'choose'),
        @('Space', 'pick or unpick (questions with several answers)'), @('y n', 'yes, no'),
        @('< Backspace', 'the previous question, your answer filled in (until the first change; Backspace on an empty answer)'),
        @('PgUp PgDn', 'scroll the log (Home, End: top, bottom)'), @('Esc', 'stop (asked first); when done: back'))
    & $section 'THE SAME WITHOUT THE UI' @(
        @('d c s r', '.\infra\azure-setup.ps1 -DryRun | -Check | -Start | -Remove -Environment <env>'),
        @('a', '.\infra\azure-setup.ps1 -AddResource [-Kind sqlDatabase]'),
        @('x', '.\infra\azure-setup.ps1 -RemoveResource -Key <key>'),
        @('new project', '.\infra\azure-setup.ps1 -Init [-SpecFile spec.json]'),
        @('everything', '.\infra\azure-setup.ps1 -Help   and   infra\LAZYAZURE.md'))
    $bodyRows = $H - 2
    $max = [Math]::Max(0, $lines.Count - $bodyRows)
    if ($script:helpScroll -gt $max) { $script:helpScroll = $max }
    $shown = @()
    for ($i = $script:helpScroll; $i -lt $lines.Count; $i++) { $shown += , $lines[$i] }
    $rows = New-Object Collections.ArrayList
    [void]$rows.Add((Border-Top $W 'help' 'by Netmedia' 0))
    foreach ($r in (Full-Rows $bodyRows $W $shown)) { [void]$rows.Add($r) }
    [void]$rows.Add((Border-Bottom $W @(@('PgUp PgDn', 'scroll'), @('Esc ?', 'back')) 0))
    return , $rows
}

# No map yet: what this is, the catalog, and how to start.
function Draw-New([int]$W, [int]$H) {
    $lines = New-Object Collections.ArrayList
    [void]$lines.Add(@())
    [void]$lines.Add(@(S '  A NEW PROJECT' $st.title))
    [void]$lines.Add(@())
    foreach ($l in (Wrap 'This infra folder has no infra.map.json yet. A new project asks its name and the prefix of its names, then its resources one by one from the catalog (what each needs, which apps use it), writes the map and generates main.bicep. Nothing in Azure changes until a start.' ($W - 8))) { [void]$lines.Add(@(S "  $l")) }
    [void]$lines.Add(@())
    foreach ($l in (Wrap 'Or from a spec file: .\infra\azure-setup.ps1 -Init -SpecFile spec.json (infra/README.md, "A new project").' ($W - 8))) { [void]$lines.Add(@(S "  $l" $st.muted)) }
    [void]$lines.Add(@())
    [void]$lines.Add(@(S '  THE CATALOG' $st.title))
    foreach ($f in @(Get-ChildItem (Join-Path $infra 'catalog') -Filter '*.json' | Where-Object { $_.Name -ne 'roles.json' })) {
        $b = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $b.addable) { continue }
        [void]$lines.Add(@((S "   $($g.mid) " $st.accent), (S (Pad $b.title 26) $st.bold), (S $b.about $st.muted)))
    }
    $rows = New-Object Collections.ArrayList
    [void]$rows.Add((Border-Top $W 'new project' 'infra/' 0))
    foreach ($r in (Full-Rows ($H - 2) $W $lines)) { [void]$rows.Add($r) }
    [void]$rows.Add((Border-Bottom $W @(@('n', 'new project'), @('?', 'help'), @('q', 'quit')) 0))
    return , $rows
}

# --- keys ----------------------------------------------------------------------------------------------

function On-Key($K) {
    $name = $K.Name
    $ch = $K.Char
    $script:dirty = $true
    if ($name -eq 'CtrlC') {
        if ($script:screen -eq 'run' -and -not $script:run.Done) { $script:run.ConfirmStop = $true; return }
        $script:quit = $true; return
    }
    if ($script:screen -eq 'help') {
        if ($name -eq 'PgDn' -or $name -eq 'Down') { $script:helpScroll += 10 }
        elseif ($name -eq 'PgUp' -or $name -eq 'Up') { $script:helpScroll = [Math]::Max(0, $script:helpScroll - 10) }
        elseif ($name -eq 'Esc' -or $name -eq 'Enter' -or ([string]$ch) -in @('?', 'q', 'h')) { $script:screen = $script:helpBack }
        return
    }
    if ([string]$ch -eq '?' -and @('home', 'map', 'new') -contains $script:screen) { $script:helpBack = $script:screen; $script:helpScroll = 0; $script:screen = 'help'; return }
    if ($script:screen -eq 'new') {
        $c = ([string]$ch).ToLower()
        if ($c -eq 'q' -or $name -eq 'Esc') { $script:quit = $true }
        elseif ($c -eq 'n' -or $name -eq 'Enter') { Start-Run 'Init' }
        return
    }
    if ($script:screen -eq 'home') {
        $script:message = ''
        $count = $script:envs.Count
        if ($script:focus -eq 'action') { $count = $actions.Count }
        if ($name -eq 'Up' -or $name -eq 'Down') {
            $delta = 1
            if ($name -eq 'Up') { $delta = -1 }
            if ($script:focus -eq 'env') { $script:envIndex = ($script:envIndex + $delta + $count) % $count }
            else { $script:actionIndex = ($script:actionIndex + $delta + $count) % $count }
            return
        }
        if ($name -eq 'Tab' -or $name -eq 'Right' -or $name -eq 'Left') { if ($script:focus -eq 'env') { $script:focus = 'action' } else { $script:focus = 'env' }; return }
        if ($name -eq 'Enter') {
            if ($script:focus -eq 'env') { $script:focus = 'action'; return }
            $mode = $actions[$script:actionIndex].Mode
        } elseif ($name -eq 'Esc') { return }
        else {
            $c = ([string]$ch).ToLower()
            if ($c -eq 'q') { $script:quit = $true; return }
            if ($c -eq 't') { $script:refreshToken = -not $script:refreshToken; return }
            $a = $actions | Where-Object { $_.Key -eq $c } | Select-Object -First 1
            if (-not $a) { return }
            $mode = $a.Mode
        }
        if ($mode -eq 'Map') { $script:screen = 'map'; $script:mapScroll = 0; return }
        Start-Run $mode
        return
    }
    if ($script:screen -eq 'map') {
        $items = @(Get-MapItems)
        if ($name -eq 'Up') { $script:mapIndex = ($script:mapIndex - 1 + $items.Count) % $items.Count; $script:mapScroll = 0 }
        elseif ($name -eq 'Down') { $script:mapIndex = ($script:mapIndex + 1) % $items.Count; $script:mapScroll = 0 }
        elseif ($name -eq 'PgDn') { $script:mapScroll += 10 }
        elseif ($name -eq 'PgUp') { $script:mapScroll = [Math]::Max(0, $script:mapScroll - 10) }
        elseif ($name -eq 'Esc' -or $name -eq 'Back' -or ([string]$ch) -in @('q', 'm')) { $script:screen = 'home' }
        elseif ([string]$ch -eq 'a') { Start-Run 'AddResource' }
        elseif ([string]$ch -eq 'x') {
            $item = $items[$script:mapIndex]
            if ($item.Def -and @('group', 'name') -notcontains $item.Def.ask) { Start-Run 'RemoveResource' $item.Def.key }
        }
        return
    }
    # The run.
    $run = $script:run
    if ($name -eq 'PgUp') { $run.Scroll += 10; return }
    if ($name -eq 'PgDn') { $run.Scroll = [Math]::Max(0, $run.Scroll - 10); return }
    if ($name -eq 'End') { $run.Scroll = 0; return }
    if ($name -eq 'Home') { $run.Scroll = 100000; return }
    if ($run.ConfirmStop) {
        if (([string]$ch).ToLower() -eq 'y') { $run.ConfirmStop = $false; Stop-Run }
        elseif ($name -eq 'Esc' -or ([string]$ch).ToLower() -eq 'n' -or $name -eq 'Enter') { $run.ConfirmStop = $false }
        return
    }
    if ($run.Done) {
        if ($name -eq 'Enter' -or $name -eq 'Esc' -or ([string]$ch).ToLower() -eq 'q') {
            $script:screen = 'home'
            if ($mapModes -contains $run.Mode) {
                if (Test-Path (Join-Path $infra 'infra.map.json')) { Reload-Map }
                $script:screen = $run.Back
                if ($script:screen -eq 'new' -and $map) { $script:screen = 'home' }
            }
            else { $script:envs = @(Load-Environments) }
        }
        return
    }
    if ($name -eq 'Esc') { $run.ConfirmStop = $true; return }
    $ask = $run.Ask
    if (-not $ask) { return }
    # Back to the previous question: < or Backspace on an empty answer (the setup asks it again, the log rewinds).
    if ((([string]$ch -eq '<') -or $name -eq 'Back') -and $ask.canBack -and -not $run.Input) { Send-Answer '<' ''; return }
    if ($ask.Choices -and $ask.Choices.Count) {
        $n = $ask.Choices.Count
        if ($name -eq 'Left' -or $name -eq 'Up') { $run.Choice = ($run.Choice - 1 + $n) % $n; return }
        if ($name -eq 'Right' -or $name -eq 'Down' -or $name -eq 'Tab') { $run.Choice = ($run.Choice + 1) % $n; return }
        if ($ask.kind -eq 'multi') {
            $current = $ask.Choices[$run.Choice]
            if ($name -eq 'Space') { if ($run.Picked[$current]) { $run.Picked.Remove($current) } else { $run.Picked[$current] = $true }; return }
            if ($name -eq 'Enter') {
                $picked = @($ask.Choices | Where-Object { $run.Picked[$_] })
                if ($picked.Count) { Send-Answer ($picked -join ', ') ($picked -join ', ') } else { Send-Answer '-' 'none' }
            }
            return
        }
        if ($ask.kind -eq 'confirm') {
            $c = ([string]$ch).ToLower()
            if ($c -eq 'y') { Send-Answer 'y' 'Yes'; return }
            if ($c -eq 'n') { Send-Answer 'n' 'No'; return }
        } elseif ($ch -and [char]::IsDigit($ch) -and [int][string]$ch -ge 1 -and [int][string]$ch -le $n) { $run.Choice = [int][string]$ch - 1; return }
        if ($name -eq 'Enter') {
            $choice = $ask.Choices[$run.Choice]
            if ($ask.kind -eq 'confirm') { Send-Answer $choice.Substring(0, 1).ToLower() $choice } else { Send-Answer $choice $choice }
        }
        return
    }
    if ($name -eq 'Enter') {
        $shown = $run.Input
        if (-not $shown) { $shown = [string]$ask.default; if (-not $shown) { $shown = '(empty)' } }
        Send-Answer $run.Input $shown
        return
    }
    if ($name -eq 'Back') { if ($run.Input.Length) { $run.Input = $run.Input.Substring(0, $run.Input.Length - 1) }; return }
    if ($name -eq 'Space') { $run.Input += ' '; return }
    if ($ch -and [int][char]$ch -ge 32) { $run.Input += [string]$ch }
}

$keyNames = @{ UpArrow = 'Up'; DownArrow = 'Down'; LeftArrow = 'Left'; RightArrow = 'Right'; Enter = 'Enter'; Escape = 'Esc'; Tab = 'Tab'; PageUp = 'PgUp'; PageDown = 'PgDn'; Home = 'Home'; End = 'End'; Backspace = 'Back' }
function Read-Keys {
    $out = @()
    while ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { $out += [pscustomobject]@{ Name = 'CtrlC'; Char = $null }; continue }
        $name = $keyNames[$k.Key.ToString()]
        if ($k.Key -eq 'Spacebar') { $name = 'Space' }
        $char = $null
        if (-not $name -and $k.KeyChar -ne [char]0) { $char = $k.KeyChar }
        $out += [pscustomobject]@{ Name = $name; Char = $char }
    }
    return $out
}

# --- the screen ----------------------------------------------------------------------------------------

$script:prev = @()
$script:dirty = $true
function Show-Frame($Rows) {
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $line = To-Ansi $Rows[$i]
        if ($i -lt $script:prev.Count -and $script:prev[$i] -eq $line) { continue }
        [void]$sb.Append("$E[$($i + 1);1H").Append($line)
        if ($i -lt $script:prev.Count) { $script:prev[$i] = $line }
    }
    if ($script:prev.Count -ne $Rows.Count) { $script:prev = @($Rows | ForEach-Object { To-Ansi $_ }) }
    if ($sb.Length) { [Console]::Out.Write($sb.ToString()); [Console]::Out.Flush() }
}
function Get-Size {
    if ($harness) {
        $w = 120; $h = 36
        if ($Width) { $w = $Width }
        if ($Height) { $h = $Height }
        return @($w, $h)
    }
    return @(([Console]::WindowWidth - 1), [Console]::WindowHeight)
}
function Save-Frame([string]$Why) {
    if (-not $Frames) { return }
    $size = Get-Size
    $rows = Draw $size[0] $size[1]
    $text = "----- $Why -----`n" + ((@($rows | ForEach-Object { (To-Plain $_).TrimEnd() })) -join "`n") + "`n"
    [IO.File]::AppendAllText($Frames, $text, (New-Object Text.UTF8Encoding $false))
}

# The Windows console of PowerShell 5.1 shows ANSI colours once asked to (Windows 10 and later).
function Enable-Ansi {
    if ($PSVersionTable.PSEdition -eq 'Core' -or $env:OS -ne 'Windows_NT') { return }
    try {
        Add-Type -Namespace LazyAzure -Name Console -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
        $h = [LazyAzure.Console]::GetStdHandle(-11)
        $m = 0
        if ([LazyAzure.Console]::GetConsoleMode($h, [ref]$m)) { [void][LazyAzure.Console]::SetConsoleMode($h, $m -bor 4) }
    } catch { }
}

$queue = New-Object Collections.Queue
if ($Keys) { foreach ($k in $Keys.Split(',')) { if ($k -ne '') { $queue.Enqueue($k.Trim()) } } }
if ($Frames -and (Test-Path $Frames)) { Remove-Item $Frames }
# One test key (-Keys) as a key, or a wait / snapshot.
function Next-TestKey {
    if (-not $queue.Count) { return $null }
    $k = [string]$queue.Peek()
    if ($k -eq 'wait:ask') { if ($script:run -and ($script:run.Ask -or $script:run.Done)) { [void]$queue.Dequeue() }; return $null }
    if ($k -eq 'wait:done') { if ($script:run -and $script:run.Done) { [void]$queue.Dequeue() }; return $null }
    [void]$queue.Dequeue()
    if ($k -eq 'snap') { Save-Frame "snap $($script:screen)"; return $null }
    if ($k.StartsWith('text:')) { foreach ($c in $k.Substring(5).ToCharArray()) { On-Key ([pscustomobject]@{ Name = $null; Char = $c }) }; return $null }
    $names = @('Up', 'Down', 'Left', 'Right', 'Enter', 'Esc', 'Tab', 'PgUp', 'PgDn', 'Home', 'End', 'Back', 'Space', 'CtrlC')
    if ($names -contains $k) { return [pscustomobject]@{ Name = $k; Char = $null } }
    return [pscustomobject]@{ Name = $null; Char = $k[0] }
}

$code = 0
try {
    if (-not $harness) {
        Enable-Ansi
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        [Console]::TreatControlCAsInput = $true
        [Console]::Out.Write("$E[?1049h$E[?25l$E[2J")
    }
    $size = Get-Size
    $lastSpin = [Diagnostics.Stopwatch]::StartNew()
    $limit = [Diagnostics.Stopwatch]::StartNew()
    while (-not $script:quit) {
        if ($script:run -and $script:screen -eq 'run') { Update-Run }
        if ($harness) {
            $k = Next-TestKey
            if ($k) { On-Key $k }
            if (-not $queue.Count) { break }
            if ($limit.Elapsed.TotalMinutes -gt 15) { throw 'test keys: timed out' }
            if (-not $k) { Start-Sleep -Milliseconds 20 }
            continue
        }
        foreach ($k in @(Read-Keys)) { On-Key $k }
        $now = Get-Size
        if ($now[0] -ne $size[0] -or $now[1] -ne $size[1]) { $size = $now; $script:prev = @(); [Console]::Out.Write("$E[2J"); $script:dirty = $true }
        if ($script:screen -eq 'run' -and -not $script:run.Done -and $lastSpin.ElapsedMilliseconds -gt 110) { $script:tick++; $script:dirty = $true; $lastSpin.Restart() }
        if ($script:dirty) {
            Show-Frame (Draw $size[0] $size[1])
            $script:dirty = $false
        }
        Start-Sleep -Milliseconds 25
    }
    if ($harness) { Save-Frame "end $($script:screen)" }
} catch {
    $code = 1
    $err = $_
} finally {
    if ($script:run -and $script:run.Proc -and -not $script:run.Proc.HasExited) {
        if ($env:OS -eq 'Windows_NT') { & taskkill.exe /T /F /PID $script:run.Proc.Id 2>&1 | Out-Null } else { try { $script:run.Proc.Kill() } catch { } }
    }
    if (-not $harness) {
        [Console]::TreatControlCAsInput = $false
        [Console]::Out.Write("$E[0m$E[?25h$E[?1049l")
    }
}
if ($err) { Write-Host "lazyazure: $($err.Exception.Message)" -ForegroundColor Red; Write-Host $err.ScriptStackTrace -ForegroundColor DarkGray }
if (-not $harness) {
    Show-Author
    Write-Host '  .\infra\lazyazure.ps1 -Help: screens, keys and commands   |   infra\LAZYAZURE.md: everything else' -ForegroundColor DarkGray
    Write-Host ''
}
exit $code

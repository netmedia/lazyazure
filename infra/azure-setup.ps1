#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyAzure  -  azure-setup.ps1                                          ║
#  ║   A project's Azure infrastructure from one map: set up, check, change   ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyAzure  -  https://github.com/netmedia/lazyazure          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
LazyAzure by Netmedia: creates, checks and updates the whole Azure infrastructure of one environment, as
infra/infra.map.json maps it; adds and removes resources of the map; starts the map of a new project.

.AUTHOR
Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
LazyAzure (infra/LAZYAZURE.md). One environment (prod, test, stag, dev, accp) with the Azure CLI.
infra/infra.map.json lists its resources (apps, databases, queues, vaults, telemetry...), how they are
named, asked, connected and checked; infra/main.bicep, generated from it by infra/generate.ps1, creates
them. Then the apps' database users, the GitHub -> Azure trust, the GitHub environment with its variables
and deployment tokens, and the custom domains. infra/lazyazure.ps1 is the same in a terminal UI.

It also changes the map: -AddResource adds a resource of the catalog (infra/catalog) with its
connections, -RemoveResource takes one out, -Init starts the map of a new project.

It asks for the environment and every name (defaults from the naming rules in infra/naming.json, then
from the environment's saved answers), checks every step and only does what is missing, each change
asked first. Enter accepts the value in brackets; '<' goes back to the previous question (until the
answers are saved and the first change is made). When the environment's answers are saved, it first asks
"Change anything?": no (the default) keeps them all and goes straight on; yes goes through the questions.

  0. Answers: environment, subscription, prefix, the sub application name of each deployment target,
     region, every name and size of the map's resources, custom domains, the GitHub repository and the
     branch that deploys to the environment. A name found in the subscription is used (shared resources
     also from another resource group, as they are); a new one is created. Saved in
     infra/environments/<env>.json (commit it).
  1. Azure resources: resource providers, the resource group, infra/main.bicep (what-if shown first).
  2. GitHub -> Azure trust (OIDC): app registration, service principal, federated credential for the
     GitHub environment, the deploy role on each app.
  3. GitHub environment: deployments only from its branch, the map's variables and the Static Web Apps'
     deployment tokens (with the GitHub CLI; without it the script prints what to set by hand).
  4. Custom domains: shows the DNS records and checks them until they resolve ('s' skips), then adds
     the domains with free certificates.
  5. Live: the checks the map lists (an API's health and version, a web app's home page...).
  The end lists everything still open.

Idempotent: a second run with the same answers changes nothing. Everything is looked up before it is
created; the template is deployed only when what-if shows a real change; a secret the setup keeps keeps its
value and is written to the vault only when missing or different; the deployment token is set in GitHub
only when missing, when its Static Web App is new, or with -RefreshToken. The Azure CLI's default subscription
is never changed.

Run without a switch, it shows this help and then asks what to do:
  1. Dry run - asks every question, shows what would be created or changed; changes nothing.
  2. Check   - checks an environment that is set up, with its saved answers and no questions; changes
               nothing.
  3. Start   - asks every question, then creates and updates what is missing, each change asked first.
  4. Remove all - deletes what the setup created for an environment: shown first, confirmed by typing the
               resource group's name.

.PARAMETER DryRun
Dry run without the menu: asks every question (Enter = the value in brackets), compares Azure and GitHub
with the answers and reports what would be created or changed. Changes nothing, saves nothing. Exits with
1 when anything is still open.

.PARAMETER Check
Check without the menu: takes every answer from infra/environments/<env>.json (no questions besides the
environment) and reports what is in place and what is missing. Changes nothing. Exits with 1 when
anything is still open; for scheduled checks or before a release.

.PARAMETER Remove
Removes what the setup created for an environment (from its saved answers): the resources the template
made, with the resource group when nothing else is in it, the app registration GitHub Actions deploys
with, and the GitHub environment. Shared resources from other groups and anything else are kept. All of
it is shown first and confirmed by typing the resource group's name; the Key Vault can be purged (asked,
no by default), the saved answers deleted (asked, no by default). The DNS records are listed to remove by
hand.

.PARAMETER Start
Start without the menu: asks every question, then creates and updates what is missing, each change asked
first.

.PARAMETER Environment
The environment to start with: prod, test, stag, dev or accp (infra/naming.json). Without it, the
script asks (default prod).

.PARAMETER RefreshToken
Also sets the Static Web Apps' deployment tokens in the GitHub environment again, e.g. after resetting one in the
Azure portal.

.PARAMETER Currency
Currency of the estimated monthly cost (Azure list prices from prices.azure.com): EUR by default, or USD,
GBP...

.PARAMETER Ui
For infra/lazyazure.ps1: writes events instead of text (one JSON object per line, after '@@ui ') and
reads the answers from standard input, one per line. Needs -DryRun, -Check, -Start or -Remove.

.PARAMETER AddResource
Adds a resource of the catalog to infra/infra.map.json (what it needs, which apps use it), then generates
and compiles main.bicep. Nothing in Azure changes.

.PARAMETER Kind
With -AddResource: the kind to add (sqlDatabase, serviceBus, storageQueue, functionApp, appService...).

.PARAMETER RemoveResource
Takes a resource out of the map with everything that refers to it, then generates main.bicep. Azure keeps
the resource (the end says how to delete it).

.PARAMETER Key
With -RemoveResource: the resource's key in the map.

.PARAMETER Init
Starts the map of a new project (an empty instance): its name and prefix, then its resources.

.PARAMETER SpecFile
With -Init: a spec file with the project and its resources (infra/LAZYAZURE.md, "A new project"); no
questions.

.PARAMETER Help
Shows this help.

.EXAMPLE
.\infra\azure-setup.ps1
Shows the help, then asks: dry run, check or start.

.EXAMPLE
.\infra\azure-setup.ps1 -DryRun
Asks the questions, shows what exists and what would be created or changed, changes nothing.

.EXAMPLE
.\infra\azure-setup.ps1 -Check -Environment prod
Checks production with its saved answers, without questions.

.EXAMPLE
.\infra\azure-setup.ps1 -Start -Environment test
Sets up (or updates) the test environment.

.EXAMPLE
.\infra\azure-setup.ps1 -Start -RefreshToken
Also puts the Static Web Apps' current deployment tokens into GitHub again.

.NOTES
Needs: the Azure CLI signed in (az login; add --tenant if the subscription is in another tenant), Owner
(or Contributor + User Access Administrator) on the subscription and the right to create app
registrations; the GitHub CLI signed in (gh auth login) as an admin of the repository for step 3.
Runs in Windows PowerShell 5.1 and PowerShell 7, from the repository root. If scripts are blocked:
powershell -ExecutionPolicy Bypass -File .\infra\azure-setup.ps1

LazyAzure is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
https://github.com/netmedia/lazyazure.

.LINK
infra/LAZYAZURE.md
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Check,
    [switch]$Start,
    [Alias('RemoveAll')]
    [switch]$Remove,
    [string]$Environment,
    [switch]$RefreshToken,
    [Alias('h')]
    [switch]$Help,
    [string]$Currency = 'EUR',
    [switch]$Ui,
    [switch]$AddResource,
    [string]$Kind,
    [switch]$RemoveResource,
    [string]$Key,
    [switch]$Init,
    [string]$SpecFile
)

# --- Netmedia: who made it, how to use it ---------------------------------------------------------------

$kitVersion = ''
if (Test-Path (Join-Path $PSScriptRoot 'kit.json')) { $kitVersion = (Get-Content (Join-Path $PSScriptRoot 'kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version }

function Show-Author {
    $width = 64
    $hLine = [string]::new([char]0x2500, $width)
    $v = [char]0x2502
    $esc = [char]27
    function Row([string]$display, [string]$measure = $display, [string]$color = 'White') {
        $pad = [Math]::Max(0, $width - $measure.Length)
        $left = [Math]::Floor($pad / 2)
        Write-Host "  $v" -NoNewline -ForegroundColor Cyan
        Write-Host "$(' ' * $left)$display$(' ' * ($pad - $left))" -NoNewline -ForegroundColor $color
        Write-Host $v -ForegroundColor Cyan
    }
    $title = 'LazyAzure  -  azure-setup.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'A project''s Azure infrastructure from one map' -color 'White'
    Row 'set up, checked, changed and removed per environment' -color 'White'
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
    $kinds = @()
    if (Test-Path (Join-Path $PSScriptRoot 'catalog')) {
        $kinds = @(Get-ChildItem (Join-Path $PSScriptRoot 'catalog') -Filter '*.json' | Where-Object { $_.Name -ne 'roles.json' } |
                ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.addable } | ForEach-Object { $_.kind } | Sort-Object)
    }
    & $b 'USAGE'
    & $g '  .\infra\azure-setup.ps1  [mode]  [-Environment <env>]  [options]'
    & $g '  .\infra\lazyazure.ps1                         # the same in a terminal UI'
    & $d '  Run from the repository root. Without a mode: this guide, then a menu.'
    Write-Host ''
    & $b 'ENVIRONMENT MODES  (Azure; every change asked first)'
    & $y '  -DryRun'
    & $d '    Asks every question, shows what exists and what would be created or changed.'
    & $d '    Changes and saves nothing. The safe first run.'
    & $y '  -Check'
    & $d '    An environment that is set up: its saved answers, no questions; reports what is'
    & $d '    in place and what is missing. Changes nothing (exit 1 when anything is open).'
    & $y '  -Start'
    & $d '    Asks every question, then creates and updates what is missing: resources,'
    & $d '    database users, GitHub -> Azure trust (OIDC), GitHub environment, domains.'
    & $y '  -Remove  (-RemoveAll)'
    & $d '    Deletes what the setup created for an environment: shown first, confirmed by'
    & $d '    typing the resource group''s name. Shared resources and DNS stay.'
    Write-Host ''
    & $b 'MAP MODES  (infra/infra.map.json; nothing in Azure changes)'
    & $y '  -AddResource  [-Kind <kind>]'
    & $d '    Adds a resource of the catalog with its connections (what it needs, which'
    & $d '    apps use it), then generates and compiles main.bicep.'
    & $y '  -RemoveResource  -Key <key>'
    & $d '    Takes a resource out of the map with everything that refers to it; then'
    & $d '    offers to DELETE it from Azure (no by default; per environment its exact name'
    & $d '    typed, "delete prod" too for production; only what the setup made).'
    & $y '  -Init  [-SpecFile <spec.json>]'
    & $d '    Starts the map of a new project (an empty instance); a spec file answers all.'
    Write-Host ''
    & $b 'OPTIONS'
    & $y '  -Environment <env>'
    & $d "    $((@($naming.environments.PSObject.Properties | ForEach-Object { $_.Name })) -join ', ') (infra/naming.json); asked when left out."
    & $y '  -RefreshToken'
    & $d '    Puts a Static Web App''s deployment token into GitHub again (after a reset).'
    & $y '  -Currency <EUR|USD|GBP...>'
    & $d '    Currency of the estimated monthly cost (Azure list prices). Default EUR.'
    & $y '  -Help  (-h)'
    & $d '    Shows this guide and exits.'
    Write-Host ''
    if ($kinds.Count) {
        & $b 'KINDS  (infra/catalog; several of one kind are fine)'
        # Wrapped to the width of the guide.
        $line = ' '
        foreach ($k in $kinds) {
            if (($line + $k).Length -gt 76) { & $d "  $($line.TrimEnd())"; $line = ' ' }
            $line += "$k  "
        }
        & $d "  $($line.TrimEnd())"
        Write-Host ''
    }
    & $b 'EXAMPLES'
    & $g '  # A new environment: preview, then create it'
    & $g '  .\infra\azure-setup.ps1 -DryRun -Environment test'
    & $g '  .\infra\azure-setup.ps1 -Start  -Environment test'
    Write-Host ''
    & $g '  # Is production as the map says? (before a release; no questions)'
    & $g '  .\infra\azure-setup.ps1 -Check -Environment prod'
    Write-Host ''
    & $g '  # Add a SQL database (and a server, if there is none), then create it'
    & $g '  .\infra\azure-setup.ps1 -AddResource -Kind sqlDatabase'
    & $g '  .\infra\azure-setup.ps1 -Start -Environment test'
    Write-Host ''
    & $g '  # A new project from a spec file'
    & $g '  .\infra\azure-setup.ps1 -Init -SpecFile spec.json'
    Write-Host ''
    & $b 'A RUN, STEP BY STEP'
    & $d '  0. Answers (saved in infra/environments/<env>.json; Enter keeps the value in'
    & $d '     brackets, < goes back to change an answer)   1. Azure resources   Database access'
    & $d '  2. GitHub -> Azure trust   3. GitHub environment   4. Custom domains   5. Live'
    & $d '  Then the next steps by hand and everything still open.'
    Write-Host ''
    & $b 'NEEDS'
    & $d '  Azure CLI (az login), Owner on the subscription (or Contributor + User Access'
    & $d '  Administrator), the right to create app registrations; GitHub CLI (gh auth login)'
    & $d '  as an admin of the repository. Windows PowerShell 5.1 or PowerShell 7.'
    & $d '  Everything else: infra/LAZYAZURE.md'
    Write-Host $hr -ForegroundColor Cyan
    Write-Host ''
}

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8 # az and gh write UTF-8
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$infra = $PSScriptRoot
$root = Split-Path $infra -Parent
$naming = Get-Content (Join-Path $infra 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json
# An empty instance (the kit dropped into a project) has no map yet: -Init makes it.
$mapFile = Join-Path $infra 'infra.map.json'
$map = $null
$defs = @()
if (Test-Path $mapFile) {
    $map = Get-Content $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $defs = @($map.resources)
}
$staticLocations = @($map.regions.staticWebApp) # main.bicep's @allowed list
if ($Help) {
    Show-Author
    Show-Usage
    exit 0
}
$managedBy = [string]$map.project.managedByTag # the tag main.bicep puts on what it creates
$utf8 = New-Object Text.UTF8Encoding $false

$script:ui = [bool]$Ui
$script:results = New-Object System.Collections.ArrayList
$script:subscription = $null
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('infra-setup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

# The map's resources by key, and what the run learns about them: the answers (names, groups, found),
# the apps as Azure shows them, the choices (sizes, domains...), the values {braces} are filled with.
function Get-Def([string]$Key) { return $defs | Where-Object { $_.key -eq $Key } | Select-Object -First 1 }
$appTypes = @('Microsoft.Web/sites', 'Microsoft.Web/staticSites')
$script:res = [ordered]@{}
$script:apps = @{}
$script:choices = [ordered]@{}
$script:vals = @{}
$script:secrets = @{}

# --- output and questions -------------------------------------------------------------------------

# With -Ui every line is an event for infra/lazyazure.ps1.
function Send($Event) { [Console]::Out.WriteLine('@@ui ' + (ConvertTo-Json -InputObject $Event -Depth 10 -Compress)) }
function Say([string]$Text, [string]$Color) {
    if ($script:replaying) { return } # already on the screen (see Read-Answer)
    if ($script:ui) { Send ([ordered]@{ t = 'line'; text = $Text; color = $Color }); return }
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}
# While earlier answers are replayed after '<' (see Read-Answer), the output they caused is already on
# the screen, so it is not shown again.
function Head([string]$Text) {
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'head'; text = $Text }); return }
    Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan
}
function Ok([string]$Text) {
    [void]$script:results.Add(@{ Done = $true; Text = $Text })
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'ok'; text = $Text }); return }
    Write-Host "  OK $Text" -ForegroundColor Green
}
function Missing([string]$Text) {
    [void]$script:results.Add(@{ Done = $false; Text = $Text })
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'missing'; text = $Text }); return }
    Write-Host "  -- $Text" -ForegroundColor Yellow
}
function Note([string]$Text) {
    if ($script:replaying) { return }
    if ($script:ui) { Send ([ordered]@{ t = 'note'; text = $Text }); return }
    Write-Host "    $Text"
}
# What is known about a resource of the map (state: new, exists, ours, shared, problem, created, gone).
function Mark([string]$Key, [string]$Name, [string]$State, [string]$Group) {
    if ($script:ui) { Send ([ordered]@{ t = 'res'; key = $Key; name = $Name; state = $State; group = $Group }) }
}

# Going back: '<' at any question before the first change goes to the previous question. The questions
# start over and everything typed before that question is answered again by itself (quietly; matched by
# the question's text, so a question whose default changed is asked again), and every lookup runs again
# with the new answers.
$script:typed = New-Object System.Collections.ArrayList  # @{ Prompt; Answer } of this round
$script:replay = New-Object System.Collections.ArrayList # what the next round answers by itself
$script:replaying = $false
$script:previous = $null # after <: the answer given before to the question asked again
$script:canGoBack = $false
$backSignal = 'infra-setup:back'

# Reads from the console or from piped input alike. $Meta describes the question for -Ui (kind: text,
# select, confirm, menu; question, default, options).
function Read-Answer([string]$Prompt, $Meta) {
    for ($i = 0; $i -lt $script:replay.Count; $i++) {
        if ($script:replay[$i].Prompt -ne $Prompt) { continue }
        $entry = $script:replay[$i]
        $script:replay.RemoveRange(0, $i + 1)
        [void]$script:typed.Add($entry)
        $script:replaying = $script:replay.Count -gt 0
        return $entry.Answer
    }
    $script:replaying = $false
    while ($true) {
        if ($script:ui) {
            $e = [ordered]@{ t = 'ask'; prompt = $Prompt.Trim(); kind = 'text'; question = $Prompt.Trim(); default = ''; options = @() }
            if ($Meta) { foreach ($k in $Meta.Keys) { $e[$k] = $Meta[$k] } }
            $e.canBack = [bool]($script:canGoBack -and $script:typed.Count)
            if ($script:previous -and $script:previous.Prompt -eq $Prompt) { $e.previous = [string]$script:previous.Answer }
            Send $e
        } else {
            if ($script:previous -and $script:previous.Prompt -eq $Prompt -and $script:previous.Answer) { Write-Host "    (you answered: $($script:previous.Answer); Enter keeps it)" -ForegroundColor DarkGray }
            Write-Host -NoNewline $Prompt
        }
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { throw 'The input ended before every question was answered.' }
        if ([Console]::IsInputRedirected -and -not $script:ui) { Write-Host $line }
        $line = $line.Trim()
        # Asked again after '<': Enter keeps what was answered before (lazyazure fills it in instead).
        if (-not $line -and -not $script:ui -and $script:previous -and $script:previous.Prompt -eq $Prompt -and $script:previous.Answer) { $line = [string]$script:previous.Answer }
        if ($line -eq '<') {
            if (-not $script:canGoBack) { Note "X '<' goes back only while answering, before the first change"; continue }
            if (-not $script:typed.Count) { Note 'X this is the first question'; continue }
            throw $backSignal
        }
        [void]$script:typed.Add(@{ Prompt = $Prompt; Answer = $line })
        $script:previous = $null # shown once, for the question asked again
        $script:replaying = $script:replay.Count -gt 0
        return $line
    }
}
# Check mode answers every question with its saved default; the same question twice means a saved
# answer was rejected, which needs a dry run or a start to fix.
$script:lastAuto = $null
function Ask([string]$Question, [string]$Default, [string[]]$Options, [string]$Title) {
    $suffix = ''
    if ($Default) { $suffix = " [$Default]" }
    if (-not $Title) { $Title = $Question }
    if ($script:auto) {
        if ($script:lastAuto -ne $Question) {
            $script:lastAuto = $Question
            if (-not $script:ui) { Write-Host "  $Question$($suffix)" -ForegroundColor DarkGray }
            elseif (-not $script:replaying) { Send ([ordered]@{ t = 'auto'; question = $Title; value = $Default }) }
            return $Default
        }
        # The same question again: its saved answer was rejected. A check stops; a dry run or start asks it.
        if ($script:mode -eq 'check') { throw "The saved answer to '$Question' ($Default) is not valid any more: run a dry run or start to answer it again." }
        Note 'X the saved answer is not valid any more: answer this one'
    }
    $kind = 'text'
    if ($Options) { $kind = 'select' }
    $a = Read-Answer "  $Question$($suffix): " ([ordered]@{ kind = $kind; question = $Title; default = $Default; options = @($Options | Where-Object { $_ }) })
    if ($a) { return $a }
    return $Default
}
function Confirm-Step([string]$Question, [switch]$DefaultNo, [switch]$Danger) {
    if ($script:readOnly) { return $false }
    if ($DefaultNo) {
        $a = (Read-Answer "  $Question [y/N] " ([ordered]@{ kind = 'confirm'; question = $Question; default = 'n'; danger = [bool]$Danger })).ToLower()
        return $a.StartsWith('y')
    }
    $a = (Read-Answer "  $Question [Y/n] " ([ordered]@{ kind = 'confirm'; question = $Question; default = 'y' })).ToLower()
    return (-not $a) -or $a.StartsWith('y')
}
function Select-Option([string]$Question, [string[]]$Options, [string]$Default) {
    while ($true) {
        $a = Ask "$Question ($($Options -join ', '))" $Default $Options $Question
        $hit = $Options | Where-Object { $_ -ieq $a } | Select-Object -First 1
        if ($hit) { return $hit }
        Note "X one of $($Options -join ', ')"
    }
}

# --- az, gh, files --------------------------------------------------------------------------------

function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $Exe @Arguments 2>&1 } finally { $ErrorActionPreference = $prev }
    $code = $LASTEXITCODE
    $errors = @($out | Where-Object { $_ -is [Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() })
    $text = (@($out | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join "`n").Trim()
    return [pscustomobject]@{ Code = $code; Text = $text; Errors = ($errors -join "`n") }
}
# JSON answers come back as objects; lists unroll, so callers wrap them in @().
function Invoke-Az([string[]]$Arguments) {
    $all = @($Arguments)
    if ($script:subscription -and (@('ad', 'account', 'rest') -notcontains $Arguments[0])) { $all += @('--subscription', $script:subscription) }
    $all += @('--only-show-errors', '-o', 'json')
    $r = Invoke-Native 'az' $all
    if ($r.Code -ne 0) { throw "az $((@($Arguments) | Select-Object -First 4) -join ' ') failed:`n$($r.Errors)" }
    if ($r.Text) { return ($r.Text | ConvertFrom-Json) }
}
function Try-Az([string[]]$Arguments) {
    try { return Invoke-Az $Arguments } catch { }
}
# The GitHub CLI, also right after winget installed it (before a new terminal has it on the PATH).
$ghExe = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $ghExe -and (Test-Path 'C:\Program Files\GitHub CLI\gh.exe')) { $ghExe = 'C:\Program Files\GitHub CLI\gh.exe' }
function Invoke-Gh([string[]]$Arguments, [switch]$Json) {
    $r = Invoke-Native $ghExe $Arguments
    if ($r.Code -ne 0) { throw "gh $((@($Arguments) | Select-Object -First 3) -join ' ') failed:`n$($r.Errors)" }
    if ($Json) { if ($r.Text) { return ($r.Text | ConvertFrom-Json) } } else { return $r.Text }
}
function Try-Gh([string[]]$Arguments, [switch]$Json) {
    try { if ($Json) { return Invoke-Gh $Arguments -Json } else { return Invoke-Gh $Arguments } } catch { }
}
function Test-Gh([string[]]$Arguments) { return (Invoke-Native $ghExe $Arguments).Code -eq 0 }

function Write-TempJson([string]$Name, $Value) {
    $file = Join-Path $tmp $Name
    [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $Value -Depth 10 -Compress), $utf8)
    return $file
}
function Read-Json([string]$Path) {
    if (Test-Path $Path) { return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
}
function New-Secret {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
function Get-Url([string]$Url) {
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Text = [string]$r.Content }
    } catch {
        $status = 0
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        return [pscustomobject]@{ Status = $status; Text = $_.Exception.Message }
    }
}

# --- the map's values ------------------------------------------------------------------------------

# One {braces} value (infra.map.json, "$comment"), or $null while it isn't known.
function Get-Value([string]$Key) {
    if ($script:vals.ContainsKey($Key)) { return $script:vals[$Key] }
    if ($Key.StartsWith('secret.')) { return $script:secrets[$Key.Substring(7)] }
    $parts = $Key.Split('.')
    if ($parts.Count -eq 1) {
        $v = $script:choices[$Key]
        if ($v -and $v -ne '-') { return $v }
        return $null
    }
    if ($parts[1] -eq 'name' -and $script:res[$parts[0]]) { return $script:res[$parts[0]].Name }
    # Host names known from the name alone (also for a server shared from another group).
    $hostDef = Get-Def $parts[0]
    if ($parts[1] -eq 'host' -and $hostDef -and $script:res[$parts[0]] -and $script:res[$parts[0]].Name) {
        if ($hostDef.kind -eq 'sqlServer') { return $script:res[$parts[0]].Name + '.database.windows.net' }
        if ($hostDef.kind -eq 'serviceBus') { return $script:res[$parts[0]].Name + '.servicebus.windows.net' }
    }
    $app = $script:apps[$parts[0]]
    if ($app -and $parts[1] -eq 'host') { return $app.defaultHostName } # staticSites: defaultHostname (same to PowerShell)
    if ($app -and $parts[1] -eq 'id') { return $app.id }
    return $null
}
# A text with {braces} filled in; $null when one of them isn't known yet.
function Expand([string]$Text) {
    $known = $true
    $out = $Text
    foreach ($m in @([regex]::Matches($Text, '\{([^{}]+)\}'))) {
        $value = $null
        foreach ($k in $m.Groups[1].Value.Split('|')) { if (-not $value) { $value = Get-Value $k } }
        if (-not $value) { $known = $false; continue }
        $out = $out.Replace($m.Value, [string]$value)
    }
    if ($known) { return $out }
    return $null
}
function Format-Text([string]$Text, [hashtable]$Values) {
    foreach ($k in $Values.Keys) { $Text = $Text.Replace("{$k}", [string]$Values[$k]) }
    return $Text
}

# --- cost --------------------------------------------------------------------------------------------

# Azure list prices (prices.azure.com, public). Without it: the West Europe prices in EUR of 2026-10-17.
$fallbackPrices = @{ B1 = 11.53; B2 = 23.14; P0v3 = 57.16; P1v3 = 114.32; StaticStandard = 7.92; LogsPerGb = 2.63; LogsFreeGb = 5 }
$script:pricesLive = $true
function Get-RetailItems([string]$Filter) {
    $url = "https://prices.azure.com/api/retail/prices?currencyCode=$Currency&`$filter=" + [uri]::EscapeDataString($Filter)
    try { return @((Invoke-RestMethod -Uri $url -TimeoutSec 20).Items) } catch { $script:pricesLive = $false; return @() }
}
function Get-PlanMonthly([string]$Sku, [string]$Region) {
    $names = @($Sku, ($Sku -replace '^(P\d)(v\d)$', '$1 $2')) | Select-Object -Unique # P1v3 is listed as 'P1 v3'
    $or = ($names | ForEach-Object { "skuName eq '$_'" }) -join ' or '
    $hit = Get-RetailItems "serviceName eq 'Azure App Service' and armRegionName eq '$Region' and priceType eq 'Consumption' and ($or)" |
        Where-Object { $_.productName -like '*Linux*' -and $_.unitOfMeasure -eq '1 Hour' } | Select-Object -First 1
    if ($hit) { return [double]$hit.retailPrice * 730 }
    $script:pricesLive = $false
    return [double]$fallbackPrices[$Sku]
}
function Get-StaticMonthly([string]$Sku, [string]$Region) {
    if ($Sku -ne 'Standard') { return 0.0 }
    $hit = Get-RetailItems "serviceName eq 'Azure App Service' and armRegionName eq '$Region' and meterName eq 'Standard App' and priceType eq 'Consumption'" |
        Where-Object { $_.productName -like '*Static Web*' } | Select-Object -First 1
    if ($hit) { return [double]$hit.retailPrice }
    $script:pricesLive = $false
    return [double]$fallbackPrices.StaticStandard
}
function Get-LogsPrice([string]$Region) {
    $items = Get-RetailItems "serviceName eq 'Log Analytics' and armRegionName eq '$Region' and meterName eq 'Analytics Logs Data Ingestion' and priceType eq 'Consumption'"
    $paid = $items | Where-Object { [double]$_.retailPrice -gt 0 } | Select-Object -First 1
    if ($paid) { return [pscustomobject]@{ PerGb = [double]$paid.retailPrice; FreeGb = [double]$paid.tierMinimumUnits } }
    $script:pricesLive = $false
    return [pscustomobject]@{ PerGb = $fallbackPrices.LogsPerGb; FreeGb = $fallbackPrices.LogsFreeGb }
}
# The estimate of one environment's answers: what it adds to the monthly bill at list prices, one row per
# resource with a "cost" in the map. Shared resources from other groups add nothing (their own
# environment pays for them).
function Write-CostEstimate([string]$Location, [string]$StaticLocation) {
    $rows = New-Object System.Collections.ArrayList
    function Row([string]$What, $Amount, [string]$Text) { [void]$rows.Add([pscustomobject]@{ What = $What; Amount = $Amount; Text = $Text }) }
    $pennies = '< ' + (0.1).ToString('0.00') # in the current culture, like the other amounts
    foreach ($def in @($defs | Where-Object { $_.cost } | Sort-Object { [int]$_.cost.order })) {
        $r = $script:res[$def.key]
        if (-not $r -or -not $r.Name) { continue }
        $size = ''
        if ($def.size) { $size = [string]$script:choices[$def.size.answer] }
        $values = @{ name = $r.Name; size = $size; group = $r.Group }
        $label = Format-Text $def.cost.label $values
        $kind = [string]$def.cost.kind
        if ($kind -eq 'appServicePlan') {
            if ($r.Group) { Row (Format-Text $def.cost.sharedLabel $values) 0.0 '' }
            else { Row $label (Get-PlanMonthly $size $Location) '' }
        } elseif ($kind -eq 'staticWebApp') { Row $label (Get-StaticMonthly $size $StaticLocation) '' }
        elseif ($kind -eq 'pennies') { Row $label $null $pennies }
        elseif ($kind -eq 'table') {
            # A price per size (list prices, approximate), else a text, else a fixed amount.
            $price = $null
            if ($def.cost.prices -and $size -and $null -ne $def.cost.prices.$size) { $price = [double]$def.cost.prices.$size }
            $text = ''
            if ($def.cost.texts -and $size -and $def.cost.texts.$size) { $text = [string]$def.cost.texts.$size }
            if ($r.Group) { Row "$label (shared from $($r.Group))" 0.0 '' }
            elseif ($null -ne $price) { Row $label $price '' }
            elseif ($text) { Row $label $null $text }
            elseif ($def.cost.text) { Row $label $null ([string]$def.cost.text) }
            else { Row $label ([double]$def.cost.otherwise) '' }
        }
        elseif ($kind -eq 'logs') {
            $logs = Get-LogsPrice $Location
            Row $label 0.0 ('{0:0.00} up to {1:0} GB of logs a month, then {2:0.00} per GB' -f 0.0, $logs.FreeGb, $logs.PerGb)
        }
    }
    foreach ($extra in @($map.costExtras)) { if ($extra) { Row $extra 0.0 '' } }
    $total = 0.0
    foreach ($r in $rows) { if ($r.Amount) { $total += [double]$r.Amount } }
    $source = "list prices from prices.azure.com, $Location"
    if (-not $script:pricesLive) { $source = 'prices.azure.com not reachable: West Europe list prices in EUR of 2026-10' }
    $title = "Estimated monthly cost ($Currency; $source)"
    $totalText = "$($total.ToString('0.00')) $Currency a month (+ logs beyond the free amount; without VAT and discounts)"
    $shown = @(foreach ($r in $rows) {
            $amount = $r.Text
            if ($null -ne $r.Amount -and -not $r.Text) { $amount = ([double]$r.Amount).ToString('0.00') }
            [ordered]@{ what = $r.What; amount = $amount }
        })
    if ($script:ui) {
        Head $title
        Send ([ordered]@{ t = 'cost'; currency = $Currency; source = $source; rows = $shown; total = $total.ToString('0.00'); totalText = $totalText })
        return
    }
    Head $title
    foreach ($r in $shown) { Note ("{0,-64} {1}" -f $r.what, $r.amount) }
    Note ('-' * 80)
    Note ("{0,-64} {1}" -f 'Total, about', $totalText)
}

# --- names -----------------------------------------------------------------------------------------

function Fill([string]$Pattern, [string]$Type, [string]$Sub) {
    $n = $Pattern.Replace('{prefix}', $script:prefix).Replace('{sub}', $Sub).Replace('{type}', $Type).Replace('{env}', $script:envAbbr)
    return (($n -replace '-+', '-') -replace '^-|-$', '')
}
# The sub application name belongs to a deployment target (naming.json "targets": the web app, the API,
# functions...), asked for each; the environment's shared resources have none.
$script:subs = [ordered]@{}
function Get-Sub([string]$Type) {
    if ($script:subs.Contains($Type)) { return [string]$script:subs[$Type] }
    return ''
}
function Get-SavedSub([string]$Type) {
    if ($script:saved -and $script:saved.subs -and $script:saved.subs.$Type) { return [string]$script:saved.subs.$Type }
    return ''
}
function Read-Sub([string]$Type, [string]$Label, [string]$DefType) {
    while ($true) {
        $default = Get-SavedSub $Type
        # A target named after its naming type (apiapp, statapp...) starts without one; a second resource of a
        # type (another API: target api2) starts with its target as the sub application name.
        if (-not $default -and $Type -ne $DefType) { $default = $Type }
        if (-not $default) { $default = '-' }
        $s = (Ask "Sub application name of $Label ('-' for none)" $default).ToLower()
        if ($s -eq '-') { $s = '' }
        if (-not $s -or $s -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $script:subs[$Type] = $s; return }
        Note 'X lowercase letters and digits, parts separated by single hyphens'
    }
}
# The name the naming rules give a type, with the sub application name of its deployment target (by
# default the type itself: the API's target is apiapp; a second API's is api2).
function Get-RuleName([string]$Type, [string]$Target) {
    if (-not $Target) { $Target = $Type }
    $n = Fill $naming.pattern $Type (Get-Sub $Target)
    if (@($naming.noHyphens) -contains $Type) { $n = $n.Replace('-', '') }
    return $n
}
# Saved names are the defaults while the prefix (and the target's sub application name) stay the same;
# a new one starts from the rules again.
function Get-Default([string]$Key, [string]$Rule, [string]$Target) {
    if ($Target -and (Get-SavedSub $Target) -ne (Get-Sub $Target)) { return $Rule }
    if ($script:samePrefix -and $script:saved -and $script:saved.names -and $script:saved.names.$Key) { return [string]$script:saved.names.$Key }
    return $Rule
}
function Test-Name([string]$Type, [string]$Name) {
    $max = 63
    if ($naming.maxLength.$Type) { $max = [int]$naming.maxLength.$Type }
    if ($Name.Length -gt $max) { return "$Name is $($Name.Length) characters, at most $max" }
    if ($Type -eq 'store' -and $Name -notmatch '^[a-z0-9]{3,24}$') { return "${Name}: 3-24 lowercase letters and digits only" }
    if ($Type -eq 'kv' -and $Name -notmatch '^[a-z][a-z0-9-]{1,22}[a-z0-9]$') { return "${Name}: 3-24 letters, digits and hyphens, starting with a letter" }
    if ($Type -ne 'store' -and $Name -cnotmatch '^[a-z0-9][a-z0-9-]*[a-z0-9]$') { return "${Name}: lowercase letters, digits and hyphens" }
}
function Read-Name([string]$Label, [string]$Type, [string]$Default) {
    while ($true) {
        $name = (Ask $Label $Default).ToLower()
        $problem = Test-Name $Type $name
        # Several resources of one kind (two APIs...): each needs its own name (a sub application name).
        $current = $script:currentDef
        if (-not $problem -and $current) {
            foreach ($k in @($script:res.Keys)) {
                $other = Get-Def $k
                if ($k -ne $current.key -and $other -and $other.armType -eq $current.armType -and $script:res[$k].Name -ieq $name) { $problem = "$name is already the name of $($other.title) (give one of them a sub application name)" }
            }
        }
        if (-not $problem) { return $name }
        Note "X $problem"
    }
}
function Find-Resource([string]$Name, [string]$ArmType) {
    return @(Invoke-Az @('resource', 'list', '--name', $Name, '--resource-type', $ArmType)) | Where-Object { $_ -and $_.name -ieq $Name } | Select-Object -First 1
}
function Test-NameFree([string]$Provider, [string]$Type, [string]$Name, [string]$Version) {
    $url = "https://management.azure.com/subscriptions/$($script:subscription)/providers/$Provider/checkNameAvailability?api-version=$Version"
    $body = Write-TempJson 'name.json' @{ name = $Name; type = $Type }
    $r = Invoke-Az @('rest', '--method', 'post', '--url', $url, '--body', "@$body")
    # Microsoft.Sql answers "available", the other providers "nameAvailable".
    if (-not ($r.nameAvailable -or $r.available)) { return "$Name is taken: $($r.message)" }
}
function Test-InGroup($Resource) { return $Resource.resourceGroup -ieq $script:rgName }
function Test-Ours($Resource) { return ($Resource.tags -and $Resource.tags.'managed-by' -eq $managedBy -and (Test-InGroup $Resource)) }

# The map's name checks ("free": a new name; "check": an existing resource). A problem, or nothing.
function Test-Free($Def, [string]$Name) {
    switch ([string]$Def.free) {
        'nameAvailable' { return Test-NameFree $Def.armType.Split('/')[0] $Def.armType $Name $Def.apiVersion }
        'vaultSoftDelete' {
            # A deleted vault keeps its name for 30 days (soft delete).
            $deleted = Try-Az @('keyvault', 'show-deleted', '--name', $Name)
            if ($deleted) {
                if (-not (Confirm-Step "Key Vault $Name is soft-deleted ($(($deleted.properties.vaultId -split '/')[4])). Recover it?")) { return "$Name is soft-deleted (recover or purge it, or pick another name)" }
                Invoke-Az @('keyvault', 'recover', '--name', $Name) | Out-Null
                Ok "Key Vault $Name recovered"
                return
            }
            return Test-NameFree 'Microsoft.KeyVault' $Def.armType $Name $Def.apiVersion
        }
    }
}
function Test-Found($Def, $Found) {
    switch ([string]$Def.check) {
        'linuxPlanInRegion' {
            if ($Found.kind -notmatch 'linux') { return "$($Found.name) is a Windows plan; the apps on it need Linux" }
            if ($Found.location -ne $script:location) { return "$($Found.name) is in $($Found.location), the environment in $($script:location)" }
        }
        'sameRegion' {
            if ($Found.location -ne $script:location) { return "$($Found.name) is in $($Found.location), the environment in $($script:location)" }
        }
        'rbacVault' {
            if (-not (Invoke-Az @('keyvault', 'show', '--name', $Found.name, '-g', $Found.resourceGroup)).properties.enableRbacAuthorization) { return "$($Found.name) uses access policies; the API's access is an RBAC role" }
        }
    }
}

# A resource that always lives in this environment's group (ask "own"): an existing one is used only
# there; a new name must be free.
function Select-Own($Def, [string]$Label, [string]$Default) {
    while ($true) {
        $name = Read-Name $Label $Def.type $Default
        $found = Find-Resource $name $Def.armType
        $problem = $null
        if ($found -and -not (Test-InGroup $found)) { $problem = "$name exists in $($found.resourceGroup); it belongs in $($script:rgName) (pick another name)" }
        if (-not $found -and $Def.free) { $problem = Test-Free $Def $name }
        if ($problem) {
            Note "X $problem"
            if (-not $script:readOnly) { continue }
            Missing "$Label ${name}: $problem"
            Mark $Def.key $name 'problem' ''
        }
        if ($found) {
            if (Test-Ours $found) { Note 'exists, made by this template'; Mark $Def.key $name 'ours' '' }
            else { Note 'exists (not made by this template: it will be configured by it)'; Mark $Def.key $name 'exists' '' }
        } else { Note "new, created in $($script:rgName)"; if (-not $problem) { Mark $Def.key $name 'new' '' } }
        return [pscustomobject]@{ Name = $name; Group = ''; Found = $found }
    }
}

# A resource that may also be shared from another group (ask "shared"): used as it is there (Group
# set), unless it is in this group (Group empty: the template manages it).
function Select-Shared($Def, [string]$Label, [string]$Default) {
    while ($true) {
        $name = Read-Name $Label $Def.type $Default
        $found = Find-Resource $name $Def.armType
        $problem = $null
        if ($found -and $Def.check) { $problem = Test-Found $Def $found }
        if (-not $found -and $Def.free) {
            $problem = Test-Free $Def $name
            if (-not $problem) { $found = Find-Resource $name $Def.armType } # recovered from soft delete
        }
        if ($problem) {
            Note "X $problem"
            if (-not $script:readOnly) { continue }
            Missing "$Label ${name}: $problem"
            Mark $Def.key $name 'problem' ''
        }
        if (-not $found) {
            Note "new, created in $($script:rgName)"
            if (-not $problem) { Mark $Def.key $name 'new' '' }
            return [pscustomobject]@{ Name = $name; Group = ''; Found = $null }
        }
        if (Test-InGroup $found) {
            if (Test-Ours $found) { Note 'exists, made by this template: kept up to date'; Mark $Def.key $name 'ours' '' }
            else { Note 'exists in this resource group: configured by the template'; Mark $Def.key $name 'exists' '' }
            return [pscustomobject]@{ Name = $name; Group = ''; Found = $found }
        }
        Note "exists in $($found.resourceGroup) ($($found.location)): used as it is"
        Mark $Def.key $name 'shared' $found.resourceGroup
        return [pscustomobject]@{ Name = $name; Group = $found.resourceGroup; Found = $found }
    }
}

# A field of a resource, from its variant for the current choice when it has one ("variants").
function Get-Field($Def, [string]$Field) {
    if ($Def.choice -and $Def.variants) {
        $variant = $Def.variants.([string]$script:choices[$Def.choice.answer])
        if ($variant -and $null -ne $variant.$Field) { return $variant.$Field }
    }
    return $Def.$Field
}
function Test-When($Def) {
    if (-not $Def.when) { return $true }
    foreach ($p in $Def.when.PSObject.Properties) { if ([string]$script:choices[$p.Name] -ne [string]$p.Value) { return $false } }
    return $true
}

# One resource of the map: its questions (sub application name, choice, name, size), its checks.
function Read-Resource($Def) {
    $script:currentDef = $Def
    $target = [string]$Def.target
    if ($target -and -not $script:subs.Contains($target)) { Read-Sub $target $Def.targetLabel $Def.type }
    $saved = $script:saved
    if ($Def.choice) {
        $default = [string]$Def.choice.default
        if ($saved -and $saved.($Def.choice.answer)) { $default = $saved.($Def.choice.answer) }
        $script:choices[$Def.choice.answer] = Select-Option $Def.choice.label @($Def.choice.options) $default
    }
    $none = [pscustomobject]@{ Name = ''; Group = ''; Found = $null }
    if (-not (Test-When $Def)) { return $none }

    $label = [string](Get-Field $Def 'label')
    $pattern = [string](Get-Field $Def 'pattern')
    $for = [string](Get-Field $Def 'for')
    if ($pattern) { $rule = Fill $naming.$pattern $for (Get-Sub $for) } else { $rule = Get-RuleName $Def.type $target }
    $nameTarget = $target
    if (-not $nameTarget) { $nameTarget = $for }
    $default = Get-Default $Def.key $rule $nameTarget

    switch ([string]$Def.ask) {
        'own' { $r = Select-Own $Def $label $default }
        'shared' { $r = Select-Shared $Def $label $default }
        'name' { $r = [pscustomobject]@{ Name = (Read-Name $label $Def.type $default); Group = ''; Found = $null } }
        'child' {
            # A resource inside another (a database on its server, a queue in its storage account): only a name;
            # the template creates it.
            $name = Read-Name $label $Def.type $default
            $r = [pscustomobject]@{ Name = $name; Group = ''; Found = $null }
            $exists = Test-Child $Def $name
            if ($exists -eq $true) { Note 'exists'; Mark $Def.key $name 'exists' '' }
            elseif ($exists -eq $false) { Note 'new, created by the template'; Mark $Def.key $name 'new' '' }
            else { Note 'created by the template when missing'; Mark $Def.key $name 'saved' '' }
        }
        'workspace' {
            # Needed while one of its Application Insights is created or managed here; its default is the
            # workspace a managed one already uses.
            $group = ''
            if ($saved -and $saved.groups -and $saved.groups.($Def.key)) { $group = $saved.groups.($Def.key) }
            $r = [pscustomobject]@{ Name = $default; Group = $group; Found = $null }
            # One asked after it (the map's order) counts as made here.
            $users = @($Def.neededBy | Where-Object { $_ } | ForEach-Object {
                    if ($script:res.Contains($_)) { $script:res[$_] } else { [pscustomobject]@{ Name = '?'; Group = ''; Found = $null } }
                } | Where-Object { $_ -and $_.Name })
            if (@($users | Where-Object { -not $_.Group }).Count) {
                $managed = $users | Where-Object { $_.Found -and -not $_.Group } | Select-Object -First 1
                if ($managed) {
                    $linked = (Invoke-Az @('resource', 'show', '--ids', $managed.Found.id)).properties.($Def.linkProperty)
                    if ($linked) { $default = ($linked -split '/')[-1] }
                }
                $r = Select-Shared $Def $label $default
            } elseif ($script:ui) { Mark $Def.key $r.Name 'unused' $group }
        }
    }

    # The Entra admin of a server the template makes (SQL): a user's sign-in name or a group's name, saved as
    # "User|<sign-in>|<object id>" or "Group|<name>|<object id>".
    if ($Def.admin -and $r.Name -and -not $r.Group) {
        $savedAdmin = ''
        if ($saved -and $saved.($Def.admin.answer)) { $savedAdmin = [string]$saved.($Def.admin.answer) }
        $parts = $savedAdmin.Split('|')
        $defaultLogin = [string]$script:vals['me']
        if ($savedAdmin) { $defaultLogin = $parts[1] }
        while ($true) {
            $login = Ask $Def.admin.label $defaultLogin
            if ($savedAdmin -and $login -eq $parts[1]) { $script:choices[$Def.admin.answer] = $savedAdmin; break }
            $user = Try-Az @('ad', 'user', 'show', '--id', $login)
            if ($user) { $script:choices[$Def.admin.answer] = "User|$($user.userPrincipalName)|$($user.id)"; Note "Entra admin: the user $($user.displayName)"; break }
            $group = Try-Az @('ad', 'group', 'show', '--group', $login)
            if ($group) { $script:choices[$Def.admin.answer] = "Group|$($group.displayName)|$($group.id)"; Note "Entra admin: the group $($group.displayName) (its members)"; break }
            Note "X no Entra user or group $login"
        }
    }

    if ($Def.size) {
        $size = $Def.size
        $options = @($size.options)
        $value = [string]$size.default
        if ($saved -and $saved.($size.answer)) { $value = $saved.($size.answer) }
        if (-not $r.Group) {
            if ($size.readCurrent -and $r.Found) {
                $current = (Invoke-Az @('resource', 'show', '--ids', $r.Found.id)).sku.name
                if ($options -contains $current) { $value = $current }
                else { Note "the $($Def.title.ToLower()) is $current now; the template sizes it to one of these" }
            }
            if ($options -notcontains $value) { $value = [string]$size.default }
            $value = Select-Option $size.label $options $value
        }
        $script:choices[$size.answer] = $value
    }
    return $r
}

# Whether a resource inside another exists: $true, $false, or $null when it can't be told (a storage
# queue: only its data roles could list it).
function Test-Child($Def, [string]$Name) {
    if ($Def.probe -ne 'sqlDatabase') { return $null }
    $hostLink = @($map.connections | Where-Object { $_.from -eq $Def.key -and $_.kind -eq 'host' }) | Select-Object -First 1
    $server = $null
    if ($hostLink) { $server = $script:res[$hostLink.to] }
    if (-not $server -or -not $server.Name) { return $null }
    if (-not $server.Found) { return $false }
    $group = $server.Group
    if (-not $group) { $group = $script:rgName }
    return [bool](Try-Az @('sql', 'db', 'show', '-g', $group, '-s', $server.Name, '-n', $Name))
}

# --- database access (SQL): the apps' database users -----------------------------------------------------

# Azure SQL with your Entra sign-in. When the server's firewall doesn't let your address through, a start
# lets it through for this step (asked first, removed at the step's end); a check or dry run only says so.
$script:sqlRules = New-Object Collections.ArrayList
function Open-Sql([string]$Group, [string]$Server, [string]$Database) {
    $token = Try-Az @('account', 'get-access-token', '--resource', 'https://database.windows.net/')
    if (-not $token) { Missing "no Entra token for Azure SQL (az login)"; return }
    for ($try = 0; $try -lt 8; $try++) {
        $conn = New-Object System.Data.SqlClient.SqlConnection "Server=tcp:$Server.database.windows.net,1433;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30"
        $conn.AccessToken = $token.accessToken
        try { $conn.Open(); return $conn } catch {
            $msg = $_.Exception.Message
            if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
            if ($msg -match "Client with IP address '([0-9.]+)'") {
                $ip = $Matches[1]
                if (@($script:sqlRules | Where-Object { $_.Server -eq $Server }).Count) { Note 'waiting for the firewall rule...'; Start-Sleep -Seconds 15; continue }
                if ($script:readOnly) { Note "not checked: your address $ip isn't let through the firewall of $Server (a start lets it through for this step)"; return }
                if (-not (Confirm-Step "Let your address $ip through the firewall of $Server for this step (removed at its end)?")) { Missing "database access on $Server not checked (its firewall)"; return }
                Invoke-Az @('sql', 'server', 'firewall-rule', 'create', '-g', $Group, '-s', $Server, '-n', 'infra-setup', '--start-ip-address', $ip, '--end-ip-address', $ip) | Out-Null
                [void]$script:sqlRules.Add([pscustomobject]@{ Group = $Group; Server = $Server; Ip = $ip })
                Note "firewall of ${Server}: $ip let through for now"
                Start-Sleep -Seconds 15
                continue
            }
            Missing "can't sign in to $Server/${Database}: $msg (you need to be its Entra admin, or in its admin group)"
            return
        }
    }
    Missing "can't reach $Server yet (the firewall rule takes a while): run this again"
}
function Close-SqlFirewall {
    foreach ($r in @($script:sqlRules)) {
        Try-Az @('sql', 'server', 'firewall-rule', 'delete', '-g', $r.Group, '-s', $r.Server, '-n', 'infra-setup') | Out-Null
        Note "firewall of $($r.Server): $($r.Ip) closed again"
    }
    $script:sqlRules.Clear()
}
function Get-SqlRows($Conn, [string]$Text, [string]$Name) {
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Text
    [void]$cmd.Parameters.AddWithValue('@n', $Name)
    $reader = $cmd.ExecuteReader()
    $rows = @()
    while ($reader.Read()) { $rows += [string]$reader[0] }
    $reader.Close()
    return , $rows
}
function Invoke-SqlText($Conn, [string]$Text) {
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = $Text
    [void]$cmd.ExecuteNonQuery()
}
# One "sql" connection: the app's managed identity as a database user (by its client id, so the server
# needs no directory rights) with the map's database roles.
function Grant-DatabaseUser($C) {
    $appRes = $script:res[$C.from]
    $app = $script:apps[$C.from]
    $db = $script:res[$C.to]
    $hostLink = @($map.connections | Where-Object { $_.from -eq $C.to -and $_.kind -eq 'host' }) | Select-Object -First 1
    $server = $script:res[$hostLink.to]
    $group = $server.Group
    if (-not $group) { $group = $script:rgName }
    $user = [string]$appRes.Name
    $label = "$user in $($db.Name)"
    if (-not $app) { Missing "database user ${label}: the app comes first"; return }
    if (-not (Try-Az @('sql', 'db', 'show', '-g', $group, '-s', $server.Name, '-n', $db.Name))) { Missing "database user ${label}: the database comes first"; return }
    $conn = Open-Sql $group $server.Name $db.Name
    if (-not $conn) { return }
    $quoted = '[' + $user.Replace(']', ']]') + ']'
    try {
        $exists = [bool](Get-SqlRows $conn 'SELECT name FROM sys.database_principals WHERE name = @n' $user).Count
        if ($exists) { Ok "database user $label" }
        elseif (Confirm-Step "Create the database user $user in $($db.Name) (the app's managed identity signs in as it)?") {
            $sp = Invoke-Az @('ad', 'sp', 'show', '--id', $app.identity.principalId)
            $sid = '0x' + ((([guid]$sp.appId).ToByteArray() | ForEach-Object { $_.ToString('X2') }) -join '')
            Invoke-SqlText $conn "CREATE USER $quoted WITH SID = $sid, TYPE = E"
            Ok "database user $label created"
            $exists = $true
        } else { Missing "database user $label" }
        if ($exists) {
            $have = Get-SqlRows $conn 'SELECT r.name FROM sys.database_role_members m JOIN sys.database_principals r ON r.principal_id = m.role_principal_id JOIN sys.database_principals u ON u.principal_id = m.member_principal_id WHERE u.name = @n' $user
            $want = @($C.dbRoles | Where-Object { $_ })
            $lacking = @($want | Where-Object { $have -notcontains $_ })
            if (-not $lacking.Count) { Ok "$label`: $($want -join ', ')" }
            elseif (Confirm-Step "Give $user $($lacking -join ', ') in $($db.Name)?") {
                foreach ($role in $lacking) { Invoke-SqlText $conn "ALTER ROLE [$($role.Replace(']', ']]'))] ADD MEMBER $quoted" }
                Ok "$label`: $($want -join ', ')"
            } else { Missing "$label`: $($lacking -join ', ')" }
        }
    } catch { Missing "database user ${label}: $($_.Exception.Message)" }
    finally { $conn.Close() }
}

# The apps (App Service, Static Web App) as Azure shows them, or nothing.
function Get-App([string]$Key) {
    $def = Get-Def $Key
    $r = $script:res[$Key]
    if (-not $r -or -not $r.Name) { return }
    if ($def.armType -eq 'Microsoft.Web/sites') { return Try-Az @('webapp', 'show', '-g', $script:rgName, '-n', $r.Name) }
    if ($def.armType -eq 'Microsoft.Web/staticSites') { return Try-Az @('staticwebapp', 'show', '-g', $script:rgName, '-n', $r.Name) }
}
# An app's settings as name -> value (empty when it can't be read).
function Get-AppSettings([string]$Key) {
    $def = Get-Def $Key
    $name = $script:res[$Key].Name
    $have = @{}
    if ($def.armType -eq 'Microsoft.Web/sites') {
        foreach ($s in @(Try-Az @('webapp', 'config', 'appsettings', 'list', '-g', $script:rgName, '-n', $name))) { if ($s) { $have[$s.name] = [string]$s.value } }
    } elseif ($def.armType -eq 'Microsoft.Web/staticSites') {
        $s = Try-Az @('staticwebapp', 'appsettings', 'list', '-g', $script:rgName, '-n', $name)
        if ($s -and $s.properties) { foreach ($p in $s.properties.PSObject.Properties) { $have[$p.Name] = [string]$p.Value } }
    }
    return $have
}

# What-if reports noise as Modify (seen on the first real deployment): read-only values Azure adds
# (Delete: freeOfferExpirationTime, stableInboundIP, provider...), write-only defaults it never returns
# (Flow_Type, Request_Source), expressions it can't evaluate before the deployment (a role assignment's
# principalId = the API's identity), and an App Service's siteConfig, which its GET doesn't return at all
# (compared here with the real configuration instead). The template never removes a property, so a
# Delete is never a real change.
$noisePaths = @('properties.Flow_Type', 'properties.Request_Source', 'properties.siteConfig.netFrameworkVersion')
function Test-RealDelta($Delta, $SiteConfig) {
    if (@('NoEffect', 'Delete') -contains $Delta.propertyChangeType) { return $false }
    if ($noisePaths -contains $Delta.path) { return $false }
    if ($Delta.after -is [string] -and $Delta.after.StartsWith('[')) { return $false }
    if ($SiteConfig -and $Delta.path -like 'properties.siteConfig.*' -and -not $Delta.children) {
        $name = $Delta.path.Substring('properties.siteConfig.'.Length)
        if ($SiteConfig.PSObject.Properties[$name] -and "$($SiteConfig.$name)" -ieq "$($Delta.after)") { return $false }
    }
    if (-not $Delta.children) { return $true }
    foreach ($child in $Delta.children) { if (Test-RealDelta $child $SiteConfig) { return $true } }
    return $false
}
# A change of a what-if result, or $null when it is noise or what-if can't tell (Unsupported: the app
# settings, checked directly in Invoke-Setup).
function Test-RealChange($Change) {
    if (-not $Change -or @('NoChange', 'Ignore', 'Unsupported') -contains $Change.changeType) { return $false }
    if ($Change.changeType -ne 'Modify') { return $true }
    $siteConfig = $null
    if ($Change.resourceId -match '/providers/Microsoft\.Web/sites/[^/]+$') { $siteConfig = Try-Az @('webapp', 'config', 'show', '--ids', $Change.resourceId) }
    return [bool](@($Change.delta | Where-Object { Test-RealDelta $_ $siteConfig }).Count)
}

# DNS instructions, as "at the DNS host of <zone>, add <type> <name> pointing to <value>". The zone is
# taken as the last two labels (example.com); the name is relative to it, as DNS hosts want it.
$script:dnsTodo = New-Object System.Collections.ArrayList # still missing at the end of the run
function Get-Zone([string]$Domain) {
    $labels = $Domain.Split('.')
    if ($labels.Count -le 2) { return $Domain }
    return ($labels[-2..-1] -join '.')
}
function Get-RelativeName([string]$Domain) {
    $zone = Get-Zone $Domain
    if ($Domain -ieq $zone) { return '@' }
    return $Domain.Substring(0, $Domain.Length - $zone.Length - 1)
}
function New-DnsRecord([string]$Type, [string]$Name, [string]$Value) {
    return [pscustomobject]@{ Type = $Type; Name = $Name; Value = $Value; Done = $false }
}
# The records of the map's custom domains; values that exist only after creation are described instead.
function Get-DnsRecords {
    $records = @()
    foreach ($dm in @($map.domains)) {
        $domain = [string]$script:choices[$dm.answer]
        if (-not $domain -or $domain -eq '-') { continue }
        $app = $script:apps[$dm.resource]
        if ($dm.dns -eq 'staticWebApp') {
            $target = "<the $($dm.what)'s address (*.azurestaticapps.net), known once it is created>"
            if ($app) { $target = $app.defaultHostname }
            $records += New-DnsRecord 'CNAME' $domain $target
        } elseif ($dm.dns -eq 'appService') {
            $records += New-DnsRecord 'CNAME' $domain "$($script:res[$dm.resource].Name).azurewebsites.net"
            $verification = "<the verification id, known once the $($dm.what) is created>"
            if ($app) { $verification = $app.customDomainVerificationId }
            $records += New-DnsRecord 'TXT' "asuid.$domain" $verification
        }
    }
    return $records
}
function Write-DnsInstructions([string]$Title, [object[]]$Records) {
    $Records = @($Records | Where-Object { $_ })
    if (-not $Records.Count) { return }
    if ($script:ui) {
        $list = @(foreach ($r in $Records) {
                $how = 'pointing to'
                if ($r.Type -eq 'TXT') { $how = 'with the value' }
                [ordered]@{ zone = (Get-Zone $r.Name); type = $r.Type; name = $r.Name; relative = (Get-RelativeName $r.Name); how = $how; value = $r.Value; done = [bool]$r.Done }
            })
        Send ([ordered]@{ t = 'dns'; title = $Title; records = $list })
        return
    }
    Write-Host ''
    Write-Host "    $Title" -ForegroundColor Cyan
    foreach ($zone in @($Records | ForEach-Object { Get-Zone $_.Name } | Select-Object -Unique)) {
        Write-Host "    At the DNS host of $zone, add:" -ForegroundColor Cyan
        foreach ($r in @($Records | Where-Object { (Get-Zone $_.Name) -eq $zone })) {
            $how = 'pointing to'
            if ($r.Type -eq 'TXT') { $how = 'with the value' }
            $mark = '  '
            if ($r.Done) { $mark = 'OK' }
            Write-Host ("      {0} {1,-5}  {2,-30} {3,-14} {4}" -f $mark, $r.Type, (Get-RelativeName $r.Name), $how, $r.Value) -ForegroundColor Cyan
        }
        Write-Host "      (full names: $((@($Records | Where-Object { (Get-Zone $_.Name) -eq $zone } | ForEach-Object { $_.Name }) | Select-Object -Unique) -join ', '))" -ForegroundColor DarkGray
    }
}

# The issued certificate of a hostname in a resource group, or nothing. Looked up as resources, since
# 'az webapp config ssl list' leaves App Service managed certificates out (seen on production).
function Find-Certificate([string]$Group, [string]$HostName) {
    foreach ($c in @(Try-Az @('resource', 'list', '-g', $Group, '--resource-type', 'Microsoft.Web/certificates'))) {
        if (-not $c) { continue }
        $full = Try-Az @('resource', 'show', '--ids', $c.id)
        if ($full -and (@($full.properties.hostNames) -contains $HostName) -and $full.properties.thumbprint) {
            return [pscustomobject]@{ thumbprint = $full.properties.thumbprint; expires = ([string]$full.properties.expirationDate).Split('T')[0] }
        }
    }
}

function Test-Dns([string]$Host_, [object[]]$Records) {
    while ($true) {
        foreach ($r in $Records) {
            if ($r.Type -eq 'CNAME') {
                $values = @(Resolve-DnsName -Name $r.Name -Type CNAME -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'CNAME' } | ForEach-Object { $_.NameHost })
            } else {
                $values = @(Resolve-DnsName -Name $r.Name -Type TXT -DnsOnly -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'TXT' } | ForEach-Object { $_.Strings -join '' })
            }
            $r.Done = [bool](@($values | Where-Object { $_.TrimEnd('.') -ieq $r.Value }).Count)
        }
        if (@($Records | Where-Object { -not $_.Done }).Count -eq 0) {
            Ok "DNS of $Host_"
            return $true
        }
        Write-DnsInstructions "DNS for $Host_ is not there yet (OK = already resolves):" $Records
        if ($script:readOnly -or (Ask 'Enter = check DNS again (after adding it), s = skip this domain for now' '') -eq 's') {
            Missing "DNS of $Host_"
            foreach ($r in $Records) { if (-not $r.Done) { [void]$script:dnsTodo.Add($r) } }
            return $false
        }
    }
}

# Step 4 for one domain of a Static Web App: DNS, then the domain (Azure validates it and issues the
# certificate).
function Add-StaticDomain($Dm, [string]$Domain) {
    $r = $script:res[$Dm.resource]
    $app = $script:apps[$Dm.resource]
    if (-not $app) { Missing "${Domain}: the $($Dm.what) comes first"; return }
    $status = @(Try-Az @('staticwebapp', 'hostname', 'list', '-g', $script:rgName, '-n', $r.Name)) | Where-Object { $_ -and ($_.name -ieq $Domain -or $_.domainName -ieq $Domain) } | Select-Object -First 1
    if ($status -and $status.status -eq 'Ready') { Ok "https://$Domain ($($Dm.what), certificate by Azure)"; $script:domainReady[$Dm.answer] = $true }
    elseif ($status) { Missing "$Domain on the $($Dm.what): $($status.status) (validation and certificate take a few minutes)" }
    elseif (Test-Dns $Domain @(New-DnsRecord 'CNAME' $Domain $app.defaultHostname)) {
        if (Confirm-Step "Add $Domain to $($r.Name) (Azure validates it and issues the certificate, a few minutes)?") {
            Invoke-Az @('staticwebapp', 'hostname', 'set', '-g', $script:rgName, '-n', $r.Name, '--hostname', $Domain, '--no-wait') | Out-Null
            Ok "$Domain added (run -Check later to see it Ready)"
        } else { Missing "$Domain on the $($Dm.what)"; $script:domainsToAdd = $true }
    }
}
function Test-Bound([string]$Key, [string]$Name) {
    $app = $script:apps[$Key]
    return [bool]($app -and @($app.hostNameSslStates | Where-Object { $_.name -ieq $Name -and $_.sslState -eq 'SniEnabled' }).Count)
}
# Step 4 for one domain of an App Service: DNS (CNAME + TXT asuid), the hostname, a free managed
# certificate, the SNI binding.
function Add-AppServiceDomain($Dm, [string]$Domain) {
    $r = $script:res[$Dm.resource]
    $app = $script:apps[$Dm.resource]
    if (-not $app) { Missing "${Domain}: the $($Dm.what) comes first"; return }
    if (Test-Bound $Dm.resource $Domain) { Ok "https://$Domain ($($Dm.what), managed certificate)"; $script:domainReady[$Dm.answer] = $true; return }
    if (-not (Test-Dns $Domain @(
                (New-DnsRecord 'CNAME' $Domain $app.defaultHostName),
                (New-DnsRecord 'TXT' "asuid.$Domain" $app.customDomainVerificationId)))) { return }
    $added = @($app.hostNames) -contains $Domain
    if ($added) { Ok "hostname $Domain on $($r.Name)" }
    elseif (Confirm-Step "Add $Domain to $($r.Name)?") {
        Invoke-Az @('webapp', 'config', 'hostname', 'add', '-g', $script:rgName, '--webapp-name', $r.Name, '--hostname', $Domain) | Out-Null
        $added = $true
        Ok "hostname $Domain added"
    } else { Missing "hostname $Domain"; $script:domainsToAdd = $true }

    $cert = $null
    if ($added) {
        $cert = Find-Certificate $script:rgName $Domain
        if ($cert) { Ok "certificate $($cert.thumbprint) (valid until $($cert.expires))" }
        elseif (Confirm-Step "Create the free managed certificate for $Domain (a few minutes)?") {
            Invoke-Az @('webapp', 'config', 'ssl', 'create', '-g', $script:rgName, '-n', $r.Name, '--hostname', $Domain) | Out-Null
            # Azure may still be issuing it when the command returns: wait for the thumbprint.
            for ($i = 0; $i -lt 20 -and -not $cert; $i++) {
                $cert = Find-Certificate $script:rgName $Domain
                if (-not $cert) { Note 'waiting for the certificate...'; Start-Sleep -Seconds 15 }
            }
            if ($cert) { Ok "certificate $($cert.thumbprint)" }
            else { Missing "certificate for $Domain (Azure is still issuing it: run this again in a few minutes)"; $script:domainsToAdd = $true }
        } else { Missing "certificate for $Domain"; $script:domainsToAdd = $true }
    }
    if ($cert) {
        if (Confirm-Step "Bind the certificate to $Domain (SNI)?") {
            # Straight on the hostname binding: 'az webapp config ssl bind' finds certificates through the
            # same listing that leaves managed ones out.
            $binding = Write-TempJson 'binding.json' @{ properties = @{ siteName = $r.Name; hostNameType = 'Verified'; sslState = 'SniEnabled'; thumbprint = $cert.thumbprint } }
            Invoke-Az @('rest', '--method', 'put', '--url', "https://management.azure.com$($app.id)/hostNameBindings/$($Domain)?api-version=2024-04-01", '--body', "@$binding") | Out-Null
            $script:apps[$Dm.resource] = Invoke-Az @('webapp', 'show', '-g', $script:rgName, '-n', $r.Name)
            $script:domainReady[$Dm.answer] = $true
            Ok "https://$Domain ($($Dm.what), managed certificate)"
        } else { Missing "certificate not bound to $Domain"; $script:domainsToAdd = $true }
    }
}

# The order of a saved file's keys is kept, so another order of the map doesn't count as a change.
# Another environment's answers for a new one: every name of its own moved to the new environment (its
# environment part swapped, or added when it has none), shared resources from other groups kept, its
# custom domains and deploy branch left out (they belong to it).
function Copy-Answers($Source, [string]$From, [string]$To) {
    $copy = (ConvertTo-Json -InputObject $Source -Depth 10) | ConvertFrom-Json
    foreach ($p in @($copy.names.PSObject.Properties)) {
        if ($copy.groups -and $copy.groups.($p.Name)) { continue } # shared from another group: as it is
        $def = Get-Def $p.Name
        $name = [string]$p.Value
        $flat = $def -and @($naming.noHyphens) -contains $def.type
        if ($flat) {
            if ($name.EndsWith($From)) { $name = $name.Substring(0, $name.Length - $From.Length) + $To } else { $name = $name + $To }
        } else {
            $moved = [regex]::Replace($name, "(?<=^|-)$([regex]::Escape($From))(?=-|$)", $To)
            if ($moved -eq $name) { $moved = "$name-$To" }
            $name = $moved
        }
        $copy.names.($p.Name) = $name
    }
    # Custom domains follow the source's: its environment in a label swapped (dev.app.example.com ->
    # test.app.example.com), else the environment added to the first label, in the same DNS zone
    # (app.example.com -> app-test.example.com).
    foreach ($dm in @($map.domains)) {
        if (-not $copy.PSObject.Properties[$dm.answer]) { continue }
        $domain = [string]$copy.($dm.answer)
        if (-not $domain -or $domain -eq '-') { continue }
        $moved = [regex]::Replace($domain, "(?<=^|[.-])$([regex]::Escape($From))(?=[.-])", $To)
        if ($moved -eq $domain) {
            $labels = $domain.Split('.')
            $labels[0] = "$($labels[0])-$To"
            $moved = $labels -join '.'
        }
        $copy.($dm.answer) = $moved
    }
    # The deploy branch follows the source's: its full environment name (production -> test), its short one
    # (prod -> test), or the environment in the name swapped (release-prod -> release-test); else manual runs.
    if ($copy.PSObject.Properties['branch']) {
        $branch = [string]$copy.branch
        $fromFull = [string]$naming.environments.$From
        $toFull = [string]$naming.environments.$To
        $script:copyBranch = $branch # the branch a new one starts from (a start offers to create it)
        if (-not $branch -or $branch -eq '-') { $copy.branch = '-' }
        elseif ($branch -eq $fromFull) { $copy.branch = $toFull }
        elseif ($branch -eq $From) { $copy.branch = $To }
        else {
            $moved = [regex]::Replace($branch, "(?<=^|[/_.-])$([regex]::Escape($fromFull))(?=$|[/_.-])", $toFull)
            if ($moved -eq $branch) { $moved = [regex]::Replace($branch, "(?<=^|[/_.-])$([regex]::Escape($From))(?=$|[/_.-])", $To) }
            if ($moved -ne $branch) { $copy.branch = $moved } else { $copy.branch = '-'; $script:copyBranch = '' }
        }
    }
    return $copy
}

function Get-OrderedLike($New, $Old) {
    if (-not $Old) { return $New }
    $out = [ordered]@{}
    foreach ($p in $Old.PSObject.Properties) { if ($New.Contains($p.Name)) { $out[$p.Name] = $New[$p.Name] } }
    foreach ($k in $New.Keys) { if (-not $out.Contains($k)) { $out[$k] = $New[$k] } }
    return $out
}

# --- the map's files ---------------------------------------------------------------------------------

# JSON as the map is written by hand: two spaces, short objects and lists on one line, a blank line
# between the top-level sections (a "$x" comment stays with the "x" after it), text as it is.
function Get-JsonText([string]$Text) {
    $sb = New-Object Text.StringBuilder '"'
    foreach ($c in $Text.ToCharArray()) {
        switch ($c) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default { if ([int]$c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) } else { [void]$sb.Append($c) } }
        }
    }
    return $sb.Append('"').ToString()
}
function Get-JsonProps($Value) {
    if ($Value -is [Collections.IDictionary]) { return @(foreach ($k in $Value.Keys) { , @([string]$k, $Value[$k]) }) }
    return @(foreach ($p in $Value.PSObject.Properties) { , @($p.Name, $p.Value) })
}
function Test-JsonObject($Value) { return ($Value -is [Collections.IDictionary] -or $Value -is [Management.Automation.PSCustomObject]) }
function Get-JsonCompact($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } return 'false' }
    if ($Value -is [string]) { return Get-JsonText $Value }
    if ($Value -is [ValueType]) { return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture) }
    if (Test-JsonObject $Value) {
        $props = @(Get-JsonProps $Value)
        if (-not $props.Count) { return '{}' }
        return '{ ' + ((@($props | ForEach-Object { (Get-JsonText $_[0]) + ': ' + (Get-JsonCompact $_[1]) })) -join ', ') + ' }'
    }
    $items = @($Value)
    if (-not $items.Count) { return '[]' }
    return '[' + ((@($items | ForEach-Object { Get-JsonCompact $_ })) -join ', ') + ']'
}
function Get-JsonPretty($Value, [int]$Level) {
    $pad = '  ' * $Level
    $compact = Get-JsonCompact $Value
    $isObject = Test-JsonObject $Value
    $isList = -not $isObject -and $Value -isnot [string] -and $Value -is [Collections.IEnumerable]
    if ((-not $isObject -and -not $isList) -or ($Level -gt 0 -and $pad.Length + $compact.Length -le 110)) { return $compact }
    $inner = '  ' * ($Level + 1)
    if ($isList) {
        $items = @($Value)
        if (-not $items.Count) { return '[]' }
        return "[`n" + ((@($items | ForEach-Object { $inner + (Get-JsonPretty $_ ($Level + 1)) })) -join ",`n") + "`n$pad]"
    }
    $props = @(Get-JsonProps $Value)
    if (-not $props.Count) { return '{}' }
    $out = @()
    for ($i = 0; $i -lt $props.Count; $i++) {
        $line = $inner + (Get-JsonText $props[$i][0]) + ': ' + (Get-JsonPretty $props[$i][1] ($Level + 1))
        if ($Level -eq 0 -and $i -gt 0 -and -not ([string]$props[$i - 1][0]).StartsWith('$')) { $line = "`n" + $line }
        $out += $line
    }
    return "{`n" + ($out -join ",`n") + "`n$pad}"
}
function Write-JsonFile([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, (Get-JsonPretty $Value 0) + "`n", $utf8)
}
function Set-Prop($Object, [string]$Name, $Value) {
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value } else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# --- adding and removing resources (the catalog) -------------------------------------------------------

function Get-Blueprint([string]$Kind) {
    $file = Join-Path $infra "catalog\$Kind.json"
    if (-not (Test-Path $file)) { throw "No blueprint for $Kind (infra/catalog/$Kind.json)." }
    return Read-Json $file
}
function Get-Blueprints {
    return @(Get-ChildItem (Join-Path $infra 'catalog') -Filter '*.json' | Where-Object { $_.Name -ne 'roles.json' } | ForEach-Object { Read-Json $_.FullName })
}
function Test-Answers($When, [hashtable]$Answers) {
    if (-not $When) { return $true }
    foreach ($p in $When.PSObject.Properties) { if ([string]$Answers[$p.Name] -ne [string]$p.Value) { return $false } }
    return $true
}
# A blueprint's template with its <placeholders> filled in; list items whose "when" doesn't match the
# answers are left out. Unknown <...> (like <name> in a question) stay as they are.
function Get-Filled($Value, [hashtable]$Ph, [hashtable]$Answers) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        if ($Value -match '^<q\.(\w+)\[\]>$') { return @(([string]$Answers[$Matches[1]]).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $out = $Value
        foreach ($k in $Ph.Keys) { $out = $out.Replace("<$k>", [string]$Ph[$k]) }
        return $out
    }
    if (Test-JsonObject $Value) {
        $o = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $o[$p.Name] = Get-Filled $p.Value $Ph $Answers }
        return [pscustomobject]$o
    }
    if ($Value -is [Collections.IEnumerable]) {
        $list = @(foreach ($item in @($Value)) {
                if ((Test-JsonObject $item) -and $item.PSObject.Properties['when']) {
                    if (-not (Test-Answers $item.when $Answers)) { continue }
                    $copy = Get-Filled $item $Ph $Answers
                    $copy.PSObject.Properties.Remove('when')
                    , $copy
                } else { , (Get-Filled $item $Ph $Answers) }
            })
        return , $list
    }
    return $Value
}
# Placeholders by exact name (<key>, <Key> and <KEY> are three): a case-sensitive table.
function New-Placeholders([string]$K, [string]$Title) {
    $ph = New-Object Collections.Hashtable ([StringComparer]::Ordinal)
    $ph['key'] = $K; $ph['Key'] = Get-Pascal $K; $ph['KEY'] = Get-Upper $K; $ph['title'] = $Title
    return $ph
}
function Get-Pascal([string]$Key) { return $Key.Substring(0, 1).ToUpper() + $Key.Substring(1) }
function Get-Upper([string]$Key) { return ($Key -creplace '([a-z0-9])([A-Z])', '$1_$2').ToUpper() }
function Get-MapKeys { return @($map.resources | ForEach-Object { $_.key }) }
function Add-Connection($Connection) {
    $map.connections = @($map.connections) + $Connection
    # Log Analytics knows the Application Insights that need it (main.bicep creates it only for them).
    if ($Connection.kind -eq 'logs') {
        $ws = Get-Def $Connection.to
        if ($ws -and @($ws.neededBy) -notcontains $Connection.from) { Set-Prop $ws 'neededBy' (@(@($ws.neededBy) | Where-Object { $_ }) + $Connection.from) }
    }
    Note "connection: $($Connection.from) -> $($Connection.to) ($($Connection.kind)$(if ($Connection.roles) { ': ' + (@($Connection.roles) -join ', ') }))"
}
# A resource's short tag, from the map alone: a choice per environment ("shared/separate"), or that it
# exists only for some answers ("only if separate"). Empty for the rest; a "tag" in the map wins.
function Get-Tag($Def) {
    if (-not $Def) { return '' }
    if ($Def.tag) { return [string]$Def.tag }
    if ($Def.when) { return 'only if ' + ((@($Def.when.PSObject.Properties | ForEach-Object { [string]$_.Value })) -join ', ') }
    if ($Def.choice) { return (@($Def.choice.options) -join '/') }
    return ''
}
function Select-Many([string]$Question, [string[]]$Options, [string[]]$Default) {
    # From a spec (-Init -Spec): the defaults are its answers.
    if ($script:auto) {
        $picked = @($Default | Where-Object { $_ -and $Options -contains $_ })
        $shown = '-'
        if ($picked.Count) { $shown = $picked -join ', ' }
        if (-not $script:ui) { Write-Host "  $Question [$shown]" -ForegroundColor DarkGray }
        else { Send ([ordered]@{ t = 'auto'; question = $Question; value = $shown }) }
        return $picked
    }
    # Resources of the map carry their tag (shared/separate, only if separate...).
    $labels = @($Options | ForEach-Object { $t = Get-Tag (Get-Def $_); if ($t) { "$_ · $t" } else { $_ } })
    $listed = @($Options | ForEach-Object { $t = Get-Tag (Get-Def $_); if ($t) { "$_ [$t]" } else { $_ } })
    while ($true) {
        $d = '-'
        if (@($Default).Count) { $d = @($Default) -join ', ' }
        $a = Read-Answer "  $Question ($($listed -join ', '); comma-separated, '-' for none) [$d]: " ([ordered]@{ kind = 'multi'; question = $Question; default = $d; options = @($Options); labels = $labels })
        if (-not $a) { $a = $d }
        if ($a -eq '-') { return @() }
        $picked = @($a.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $bad = @($picked | Where-Object { $Options -notcontains $_ })
        if (-not $bad.Count) { return $picked }
        Note "X not one of them: $($bad -join ', ')"
    }
}
# What a resource gives an app that uses it (the blueprint's "users"): the connection with its roles,
# the app's settings.
function Add-Use([string]$AppKey, [string]$ResKey, $Users, [hashtable]$Ph, $RoleDefault) {
    $app = Get-Def $AppKey
    $p = $Ph.Clone()
    $p['app'] = $AppKey; $p['App'] = Get-Pascal $AppKey; $p['APP'] = Get-Upper $AppKey; $p['app.title'] = $app.title
    $c = Get-Filled $Users.connection $p @{}
    Set-Prop $c 'from' $AppKey
    Set-Prop $c 'to' $ResKey
    if ($Users.roles) {
        $defaultRoles = @($Users.roles.default)
        if ($RoleDefault) { $defaultRoles = @($RoleDefault) }
        $roles = Select-Many (Get-Filled $Users.roles.question $p @{}) @($Users.roles.options) $defaultRoles
        if (-not $roles.Count) { Note "$AppKey gets no role on $ResKey"; return }
        Set-Prop $c 'roles' $roles
    }
    $ordered = [ordered]@{ from = $c.from; to = $c.to }
    foreach ($q in $c.PSObject.Properties) { if (@('from', 'to') -notcontains $q.Name) { $ordered[$q.Name] = $q.Value } }
    Add-Connection ([pscustomobject]$ordered)
    $settings = @($app.appSettings | Where-Object { $_ })
    $filled = Get-Filled $Users.settings $p @{} # a list (not wrapped again in @())
    foreach ($s in $filled) {
        if (-not $s) { continue }
        if (@($settings | Where-Object { $_.name -eq $s.name }).Count) { Note "${AppKey}: $($s.name) is already set, kept"; continue }
        $settings += $s
        Note "${AppKey}: setting $($s.name) = $($s.value)"
    }
    Set-Prop $app 'appSettings' $settings
}

# The runtimes Azure offers now on Linux (az): "web" (App Service: DOTNETCORE|10.0, NODE|22-lts...) or
# "function" (Functions: DOTNET-ISOLATED|10.0, Node|22...). Empty when az can't tell (then any is taken).
function Get-Runtimes([string]$Which) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { return @() }
    if ($Which -eq 'web') { return @(Try-Az @('webapp', 'list-runtimes', '--os', 'linux') | Where-Object { $_ } | ForEach-Object { ([string]$_) -replace '^([^:]+):', '$1|' }) }
    return @(Try-Az @('functionapp', 'list-runtimes', '--os', 'linux') | Where-Object { $_ -and $_.linux_fx_version } | ForEach-Object { [string]$_.linux_fx_version })
}
# When a runtime's support ends, as Azure reports it (Functions' Flex Consumption list has the dates;
# App Service's .NET, Node, Python versions end with the same ones). $null when unknown.
function Get-RuntimeEnd([string]$Runtime) {
    $parts = $Runtime.Split('|')
    $name = $parts[0].ToLower()
    if ($name -eq 'dotnetcore' -or $name -eq 'dotnet') { $name = 'dotnet-isolated' }
    $version = ($parts[-1] -replace '[^0-9.].*$', '') -replace '\.0$', ''
    $list = @(Try-Az @('functionapp', 'list-flexconsumption-runtimes', '--location', [string]$map.regions.default, '--runtime', $name))
    foreach ($r in $list) {
        if (-not $r -or -not $r.endOfLifeDate) { continue }
        $v = ([string]$r.sku.functionAppConfigProperties.runtime.version) -replace '\.0$', ''
        if ($v -ne $version) { continue }
        $words = ([string]$r.endOfLifeDate).Split(' ')
        try { return [datetime]::ParseExact("$($words[1]) $($words[2]) $($words[3])", 'MMM d yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
    }
    return $null
}
# A runtime question: what Azure offers now, refused otherwise; a warning when its support ends within a
# year. Flex Consumption runs dotnet-isolated, node, python, java and powershell.
function Read-Runtime([string]$Label, [string]$Default, [string]$Which, [string]$Hosting) {
    $offered = @(Get-Runtimes $Which)
    if ($Hosting -eq 'flex') { $offered = @($offered | Where-Object { $_ -match '^(DOTNET-ISOLATED|Node|Python|Java|PowerShell)\|' }) }
    if ($offered.Count) {
        $line = 'Azure offers now:'
        foreach ($o in $offered) {
            if (($line + $o).Length -gt 100) { Note $line; $line = '   ' }
            $line += " $o"
        }
        Note $line
    }
    while ($true) {
        $v = Ask $Label $Default
        if (-not $offered.Count -or $offered -contains $v) { break }
        Note "X $v isn't one Azure offers now (the list above)"
    }
    $end = Get-RuntimeEnd $v
    if ($end -and $end -lt (Get-Date).AddMonths(12)) {
        Say "    $v ends its support on $($end.ToString('yyyy-MM-dd')): a newer version is safer ('<' goes back to change it)." 'Yellow'
    } elseif ($end) { Note "$v is supported until $($end.ToString('yyyy-MM-dd'))" }
    return $v
}

# One resource from its blueprint, with what it needs first (recursively). Returns its key.
function Add-FromBlueprint([string]$Kind, [hashtable]$Preset, $Spec) {
    $bp = Get-Blueprint $Kind
    $taken = Get-MapKeys
    if ($Preset) {
        $title = $Preset.title
        $newKey = $Preset.key
        Head "$($bp.title): $title"
    } else {
        Head "$($bp.title)"
        Note $bp.about
        $count = @($map.resources | Where-Object { $_.kind -eq $Kind }).Count
        $default = [string]$bp.title
        if ($count) { $default = "$($bp.title) $($count + 1)" }
        if ($Spec -and $Spec.title) { $default = [string]$Spec.title }
        $title = Ask "Title of the new $($bp.title)" $default
        $suggest = [string]$bp.keyDefault
        for ($i = 2; $taken -contains $suggest; $i++) { $suggest = "$($bp.keyDefault)$i" }
        if ($Spec -and $Spec.key) { $suggest = [string]$Spec.key }
        while ($true) {
            $newKey = Ask 'Key in the map (letters and digits, starting with a small letter)' $suggest
            if ($newKey -cnotmatch '^[a-z][A-Za-z0-9]*$') { Note 'X letters and digits, starting with a small letter'; continue }
            if ($taken -contains $newKey) { Note "X $newKey is in the map already"; continue }
            break
        }
    }
    $answers = @{}
    $ph = New-Placeholders $newKey $title
    foreach ($q in @($bp.questions | Where-Object { $_ })) {
        $label = Get-Filled $q.label $ph @{}
        $qd = [string](Get-Filled ([string]$q.default) $ph @{})
        if ($Spec -and $Spec.answers -and $null -ne $Spec.answers.($q.id)) { $qd = [string]$Spec.answers.($q.id) }
        if ($q.runtimes) { $answers[$q.id] = Read-Runtime $label $qd ([string]$q.runtimes) ([string]$answers['hosting']) }
        elseif ($q.options) { $answers[$q.id] = Select-Option $label @($q.options) $qd } else { $answers[$q.id] = Ask $label $qd }
        $v = [string]$answers[$q.id]
        $ph["q.$($q.id)"] = $v
        $ph["q.$($q.id).name"] = $v.Split('|')[0].ToLower()
        $ph["q.$($q.id).version"] = $v.Split('|')[-1]
    }
    # Its own sub application name (several APIs...): the naming type, or the key when that is taken.
    $target = [string]$bp.naming.type
    if (@($map.resources | Where-Object { $_.target -eq $target -or $_.type -eq $target }).Count) { $target = $newKey.ToLower() }
    $ph['target'] = $target

    $links = @()
    foreach ($c in @($bp.creates | Where-Object { $_ -and (Test-Answers $_.when $answers) })) {
        $subKey = [string](Get-Filled $c.key $ph $answers)
        $sub = Add-FromBlueprint $c.kind @{ key = $subKey; title = [string](Get-Filled $c.title $ph $answers) }
        $links += , @($sub, $c.connection)
        if ($c.connection.kind -eq 'host') { $ph['host'] = $sub; $ph['host.title'] = (Get-Def $sub).title }
    }
    foreach ($r in @($bp.requires | Where-Object { $_ -and (Test-Answers $_.when $answers) })) {
        $have = @($map.resources | Where-Object { $_.kind -eq $r.kind } | ForEach-Object { $_.key })
        $question = Get-Filled $r.question $ph $answers
        $want = $null
        if ($Spec -and $Spec.requires -and $Spec.requires.($r.kind)) { $want = [string]$Spec.requires.($r.kind) }
        if ($have.Count) {
            if (-not $want) { $want = $have[0] }
            $chosen = Select-Option $question (@($have) + 'new') $want
        } else { Note "$question There is none in the map yet: a new one comes first."; $chosen = 'new' }
        if ($chosen -eq 'new') { $chosen = Add-FromBlueprint $r.kind $null; Head "$($bp.title): $title" }
        $links += , @($chosen, $r.connection)
        if ($r.field) { $ph[[string]$r.field] = $chosen }
        if ($r.connection.kind -eq 'host') { $ph['host'] = $chosen; $ph['host.title'] = (Get-Def $chosen).title }
    }

    $entry = Get-Filled $bp.entry $ph $answers
    if ($entry.PSObject.Properties['healthCheckPath'] -and $entry.healthCheckPath -eq '-') { $entry.healthCheckPath = '' }
    # The catalog's workflows build .NET: another runtime gets no generated deploy (its workflow by hand).
    if ($entry.deploy -and $entry.deploy.dotnet -and $entry.runtime -and $entry.runtime -notmatch '^DOTNET') {
        $entry.PSObject.Properties.Remove('deploy')
        Note "$($entry.runtime): the catalog's deploy workflows build .NET; write the workflow of $newKey by hand (infra/route.ps1 picks the environment)"
    }
    if ($entry.deploy) { Note "deploy: .github/workflows/$($entry.deploy.workflow) builds $($entry.deploy.source)/ on a push to an environment's branch" }
    # Before the app registration (kept last, like in the setup's questions).
    $list = @($map.resources)
    $at = $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].kind -eq 'entraDeployApp') { $at = $i; break } }
    $map.resources = @($list | Select-Object -First $at) + $entry + @($list | Select-Object -Skip $at)
    $script:defs = @($map.resources)
    Note "resource: $newKey ($Kind) - $title"
    foreach ($l in $links) {
        $c = [ordered]@{ from = $newKey; to = $l[0] }
        foreach ($q in (Get-Filled $l[1] $ph $answers).PSObject.Properties) { $c[$q.Name] = $q.Value }
        Add-Connection ([pscustomobject]$c)
    }

    # Apps that use it (its "users"), or, for a new app, what it uses.
    if ($bp.users) {
        $apps = @($map.resources | Where-Object { @($bp.users.kinds) -contains $_.kind -and $_.key -ne $newKey } | ForEach-Object { $_.key })
        # An app sends its telemetry to one Application Insights: the ones that have it already are left out.
        if ($bp.users.connection.kind -eq 'telemetry') {
            $have = @($apps | Where-Object { $a = $_; @($map.connections | Where-Object { $_.from -eq $a -and $_.kind -eq 'telemetry' }).Count })
            if ($have.Count) { Note "$($have -join ', ') send their telemetry elsewhere already: not offered" }
            $apps = @($apps | Where-Object { $have -notcontains $_ })
        }
        if ($apps.Count) {
            $defaultApps = @($apps | Select-Object -First 1)
            if ($script:specData) { $defaultApps = @($Spec.users | Where-Object { $_ }) }
            foreach ($a in (Select-Many (Get-Filled $bp.users.question $ph $answers) $apps $defaultApps)) {
                $rd = $null
                if ($Spec -and $Spec.roles -and $Spec.roles.$a) { $rd = @($Spec.roles.$a) }
                Add-Use $a $newKey $bp.users $ph $rd
            }
        }
    }
    if ($bp.app) {
        $usable = @()
        foreach ($d in @($map.resources)) {
            if ($d.key -eq $newKey -or -not $d.kind) { continue }
            # Only what every environment has (not one that exists only for some answers, like a separate
            # Application Insights of the web app).
            if ($d.when -or $d.optional) { continue }
            $dbp = $null
            if (Test-Path (Join-Path $infra "catalog\$($d.kind).json")) { $dbp = Get-Blueprint $d.kind }
            if ($dbp -and $dbp.users -and @($dbp.users.kinds) -contains $Kind -and -not @($map.connections | Where-Object { $_.from -eq $newKey -and $_.to -eq $d.key }).Count) { $usable += $d.key }
        }
        if ($usable.Count) {
            $defaultUses = @()
            if ($Spec -and $Spec.uses) { $defaultUses = @($Spec.uses) }
            # One Application Insights per app (one telemetry connection string).
            while ($true) {
                $uses = @(Select-Many "What does $title use" $usable $defaultUses)
                $telemetry = @($uses | Where-Object { (Get-Def $_).kind -eq 'appInsights' })
                if ($telemetry.Count -le 1) { break }
                Note "X one Application Insights per app (its telemetry goes to one): pick one of $($telemetry -join ', ')"
            }
            foreach ($u in $uses) {
                $ud = Get-Def $u
                $ubp = Get-Blueprint $ud.kind
                $uph = New-Placeholders $u $ud.title
                $uhost = @($map.connections | Where-Object { $_.from -eq $u -and $_.kind -eq 'host' }) | Select-Object -First 1
                if ($uhost) { $uph['host'] = $uhost.to; $uph['host.title'] = (Get-Def $uhost.to).title }
                $rd = $null
                if ($Spec -and $Spec.roles -and $Spec.roles.$u) { $rd = @($Spec.roles.$u) }
                Add-Use $newKey $u $ubp.users $uph $rd
            }
        }
    }
    # GitHub: the deploy role and the app's name for the workflows, or a Static Web App's token.
    if ($bp.github) {
        $gh = Get-Filled $bp.github $ph $answers
        if ($gh.deployRole) {
            $map.github.deployRoles = @(@($map.github.deployRoles) | Where-Object { $_ }) + [pscustomobject][ordered]@{ role = $gh.deployRole; resource = $newKey }
            Note "GitHub Actions' app registration: $($gh.deployRole) on $newKey"
        }
        if ($gh.variable) { Set-Prop $map.github.variables $gh.variable "{$newKey.name}"; Note "GitHub variable $($gh.variable) = {$newKey.name}" }
        if ($gh.tokenSecret) {
            $map.github.tokenSecrets = @(@($map.github.tokenSecrets) | Where-Object { $_ }) + [pscustomobject][ordered]@{ name = $gh.tokenSecret; resource = $newKey }
            Note "GitHub secret $($gh.tokenSecret): the deployment token of $newKey"
        }
    }
    # The naming type, providers, steps and delete order it brings.
    if ($bp.naming -and -not $naming.types.($bp.naming.type)) {
        Set-Prop $naming.types $bp.naming.type ([string]$bp.naming.about)
        if ($bp.naming.maxLength) { Set-Prop $naming.maxLength $bp.naming.type ([int]$bp.naming.maxLength) }
        $script:namingChanged = $true
        Note "naming type: $($bp.naming.type) ($($bp.naming.about))"
    }
    foreach ($p in @($bp.providers | Where-Object { $_ })) { if (@($map.providers) -notcontains $p) { $map.providers = @($map.providers) + $p; Note "resource provider: $p" } }
    foreach ($s in @($bp.steps | Where-Object { $_ })) {
        $steps = @($map.steps.setup)
        if ($steps -contains $s.name) { continue }
        $at = [array]::IndexOf($steps, [string]$s.after)
        if ($at -lt 0) { $at = $steps.Count - 1 }
        $map.steps.setup = @($steps[0..$at]) + $s.name + @($steps | Select-Object -Skip ($at + 1))
        Note "step: $($s.name)"
    }
    if ($bp.removeOrder) {
        foreach ($t in @($bp.removeOrder.types)) {
            $order = @($map.removeOrder)
            if (@($order | Where-Object { $_ -ieq $t }).Count) { continue }
            $at = $order.Count
            foreach ($b in @($bp.removeOrder.before)) { $i = [array]::IndexOf(@($order | ForEach-Object { $_.ToLower() }), $b.ToLower()); if ($i -ge 0 -and $i -lt $at) { $at = $i } }
            $map.removeOrder = @($order | Select-Object -First $at) + $t + @($order | Select-Object -Skip $at)
        }
    }
    return $newKey
}

# Each round of a map mode (and each '<') starts from the files as they are: nothing half-added stays.
function Reset-MapState {
    $script:map = $null
    $script:defs = @()
    if (Test-Path $mapFile) {
        $script:map = Get-Content $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:defs = @($script:map.resources)
    }
    $script:naming = Get-Content (Join-Path $infra 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:namingChanged = $false
    $script:specData = $null
}

function Save-Map {
    $script:canGoBack = $false # files are written from here on
    Write-JsonFile (Join-Path $infra 'infra.map.json') $map
    Ok 'infra/infra.map.json written'
    if ($script:namingChanged) { Write-JsonFile (Join-Path $infra 'naming.json') $naming; Ok 'infra/naming.json written' }
    Head 'Generate'
    & (Join-Path $infra 'generate.ps1') -Quiet
    if ($LASTEXITCODE -ne 0) { Missing "infra/generate.ps1 failed: main.bicep isn't up to date"; return }
    Ok "infra/$($map.project.template) generated"
    if (Get-Command az -ErrorAction SilentlyContinue) {
        $r = Invoke-Native 'az' @('bicep', 'build', '--file', (Join-Path $infra $map.project.template), '--stdout')
        if ($r.Code -eq 0) { Ok "infra/$($map.project.template) compiles" } else { Missing "infra/$($map.project.template) doesn't compile: $($r.Errors)" }
    }
}

function Invoke-AddResource {
    Say 'Add a resource: asks what it is and what it connects to, then writes the map and generates main.bicep. Nothing in Azure changes yet.' 'Cyan'
    $script:namingChanged = $false
    $addable = @(Get-Blueprints | Where-Object { $_.addable } | Sort-Object kind)
    $kinds = @($addable | ForEach-Object { $_.kind })
    Head 'Resource'
    if ($Kind -and $kinds -contains $Kind) { $k = $Kind; Note "kind: $Kind" }
    else {
        foreach ($b in $addable) { Note ("{0,-16} {1}" -f $b.kind, $b.title) }
        $k = Select-Option 'Kind of resource' $kinds 'sqlDatabase'
    }
    $before = ConvertTo-Json -InputObject $map -Depth 20 -Compress
    $newKey = Add-FromBlueprint $k $null
    Head 'Changes'
    if (-not (Confirm-Step "Write infra/infra.map.json$(if ($script:namingChanged) { ' and naming.json' }) and generate main.bicep?")) {
        Note 'nothing was written'
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 1; cancelled = $true }) }
        return 1
    }
    Save-Map
    Head 'Next steps'
    Note "A dry run asks the names of what is new and shows what would be created: .\infra\azure-setup.ps1 -DryRun"
    Note 'then a start creates it (environment by environment); commit infra/ (the map, naming.json, main.bicep).'
    $open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text })
    if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = $open; code = [int][bool]$open.Count; added = $newKey }) }
    else { Write-Host ''; Write-Host "$newKey added to the map." -ForegroundColor Green }
    return [int][bool]$open.Count
}

# A resource of the map as an environment has it in Azure (its saved answers): id, type, group and
# whether the setup made it (the template's managed-by tag; a storage queue can't be tagged). $null when
# it isn't there.
function Find-MapResource($Def, $Saved, [string]$HostKey) {
    $name = [string]$Saved.names.($Def.key)
    $rg = [string]$Saved.names.resourceGroup
    $hostName = ''
    $hostGroup = $rg
    if ($HostKey) {
        $hostName = [string]$Saved.names.$HostKey
        if ($Saved.groups -and $Saved.groups.$HostKey) { $hostGroup = [string]$Saved.groups.$HostKey }
    }
    if ($Def.kind -eq 'sqlDatabase') {
        if (-not $hostName) { return }
        $db = Try-Az @('sql', 'db', 'show', '-g', $hostGroup, '-s', $hostName, '-n', $name)
        if (-not $db) { return }
        return [pscustomobject]@{ Id = $db.id; Type = 'SQL database'; Group = $hostGroup; Ours = [bool]($db.tags -and $db.tags.'managed-by' -eq $managedBy) }
    }
    if ($Def.kind -eq 'storageQueue') {
        if (-not $hostName) { return }
        $id = "/subscriptions/$($Saved.subscriptionId)/resourceGroups/$hostGroup/providers/Microsoft.Storage/storageAccounts/$hostName/queueServices/default/queues/$name"
        if (-not (Try-Az @('resource', 'show', '--ids', $id))) { return }
        return [pscustomobject]@{ Id = $id; Type = "queue of $hostName"; Group = $hostGroup; Ours = $true }
    }
    $r = @(Try-Az @('resource', 'list', '-g', $rg, '--name', $name, '--resource-type', $Def.armType)) | Where-Object { $_ -and $_.name -ieq $name } | Select-Object -First 1
    if (-not $r) { return }
    return [pscustomobject]@{ Id = $r.id; Type = $Def.title; Group = $rg; Ours = [bool]($r.tags -and $r.tags.'managed-by' -eq $managedBy) }
}
# Deletes it: an app's role assignments first (they'd stay as "unknown"), a Key Vault's purge asked.
function Remove-MapResource($Def, $Found) {
    if ($Def.armType -eq 'Microsoft.Web/sites') {
        $app = Try-Az @('webapp', 'show', '--ids', $Found.Id)
        if ($app -and $app.identity -and $app.identity.principalId) {
            $ras = @(Try-Az @('role', 'assignment', 'list', '--assignee', $app.identity.principalId, '--all') | Where-Object { $_ })
            foreach ($ra in $ras) { Invoke-Az @('role', 'assignment', 'delete', '--ids', $ra.id) | Out-Null }
            if ($ras.Count) { Ok "$($ras.Count) role assignment(s) of its managed identity removed" }
        }
    }
    Note 'deleting (can take a few minutes)...'
    Invoke-Az @('resource', 'delete', '--ids', $Found.Id) | Out-Null
    if ($Def.kind -eq 'keyVault') {
        $vaultName = ($Found.Id -split '/')[-1]
        if ((Try-Az @('keyvault', 'show-deleted', '--name', $vaultName)) -and (Confirm-Step "Purge Key Vault $vaultName now (frees its name; its secrets can't be recovered then)?" -DefaultNo -Danger)) {
            Invoke-Az @('keyvault', 'purge', '--name', $vaultName) | Out-Null
            Ok "Key Vault $vaultName purged"
        }
    }
}
# The environment's saved answers without the resource (its name, group and the answers asked with it).
function Remove-SavedName([string]$File, $Saved, $Def) {
    $Saved.names.PSObject.Properties.Remove($Def.key)
    if ($Saved.groups) { $Saved.groups.PSObject.Properties.Remove($Def.key) }
    foreach ($a in @($Def.size.answer, $Def.choice.answer, $Def.admin.answer) | Where-Object { $_ }) { $Saved.PSObject.Properties.Remove($a) }
    [IO.File]::WriteAllText($File, (ConvertTo-Json -InputObject $Saved -Depth 10) + "`n", $utf8)
    Note "infra/environments/$(Split-Path $File -Leaf): $($Def.key) taken out"
}

# Takes a resource out of the map with everything that refers to it; what runs on it must go first.
function Invoke-RemoveResource {
    Say 'Remove a resource from the map: everything that refers to it goes too; Azure is not changed.' 'Cyan'
    $script:namingChanged = $false
    Head 'Resource'
    $keys = @($map.resources | Where-Object { @('group', 'name') -notcontains $_.ask } | ForEach-Object { $_.key })
    foreach ($d in @($map.resources | Where-Object { $keys -contains $_.key })) { Note ("{0,-16} {1} ({2})" -f $d.key, $d.title, $d.kind) }
    if ($Key -and $keys -contains $Key) { $k = $Key; Note "resource: $Key" } else { $k = Select-Option 'Resource to remove' $keys $keys[0] }
    $def = Get-Def $k
    # What it is in or on (a database's server, a queue's storage account): needed to find it in Azure.
    $hostKey = [string](@($map.connections | Where-Object { $_.from -eq $k -and $_.kind -eq 'host' }) | Select-Object -First 1).to
    $on = @($map.connections | Where-Object { $_.to -eq $k -and $_.kind -eq 'host' } | ForEach-Object { $_.from })
    $mirrors = @($map.resources | ForEach-Object { @($_.secrets) } | Where-Object { $_ -and $_.mirror -and $_.mirror.resource -eq $k })
    if ($on.Count -or $mirrors.Count) {
        if ($on.Count) { Missing "$k can't go while $($on -join ', ') run on it or are in it: remove them first" }
        if ($mirrors.Count) { Missing "$k keeps the secret $($mirrors[0].name) of a Key Vault (its mirror): change that in the map first" }
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text }); code = 1 }) }
        return 1
    }

    Head 'Changes'
    Note "resource: $k ($($def.kind)) $($def.title)"
    $pattern = '\{([^{}|]*\|)*' + [regex]::Escape($k) + '\.'
    $conns = @()
    foreach ($c in @($map.connections)) {
        $alts = @($c.to.Split('|'))
        if ($c.from -eq $k -or ($alts -contains $k -and $alts.Count -eq 1)) { Note "connection: $($c.from) -> $($c.to) ($($c.kind))"; continue }
        if ($alts -contains $k) { $c.to = (@($alts | Where-Object { $_ -ne $k }) -join '|'); Note "connection: $($c.from) -> $($c.to) (without $k)" }
        $conns += $c
    }
    $map.connections = $conns
    foreach ($d in @($map.resources)) {
        if ($d.key -eq $k) { continue }
        if ($d.appSettings) {
            $keep = @()
            foreach ($s in @($d.appSettings)) { if ([string]$s.value -match $pattern) { Note "$($d.key): setting $($s.name) (uses $k)" } else { $keep += $s } }
            Set-Prop $d 'appSettings' $keep
        }
        if ($d.neededBy -and @($d.neededBy) -contains $k) { Set-Prop $d 'neededBy' @(@($d.neededBy) | Where-Object { $_ -ne $k }) }
        if ($d.stateStorage -eq $k) { Missing "$($d.key) keeps its state in ${k}: give it another stateStorage first" }
    }
    $map.resources = @($map.resources | Where-Object { $_.key -ne $k })
    $script:defs = @($map.resources)
    foreach ($p in @($map.github.variables.PSObject.Properties)) { if ([string]$p.Value -match $pattern) { $map.github.variables.PSObject.Properties.Remove($p.Name); Note "GitHub variable $($p.Name)" } }
    $map.github.deployRoles = @($map.github.deployRoles | Where-Object { $_ -and $_.resource -ne $k })
    $map.github.tokenSecrets = @($map.github.tokenSecrets | Where-Object { $_ -and $_.resource -ne $k })
    foreach ($dm in @($map.domains | Where-Object { $_.resource -eq $k })) { Note "custom domain $($dm.answer)" }
    $map.domains = @($map.domains | Where-Object { $_.resource -ne $k })
    $map.live = @($map.live | Where-Object { $_.resource -ne $k })
    if (@($script:results | Where-Object { -not $_.Done }).Count) {
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text }); code = 1 }) }
        return 1
    }
    if (-not (Confirm-Step "Write infra/infra.map.json without $k and generate main.bicep?" -DefaultNo)) {
        Note 'nothing was written'
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 1; cancelled = $true }) }
        return 1
    }
    Save-Map

    # Azure: a deployment never deletes. Deleting is destructive and can't be undone, so it is never the
    # default: first a yes/no (no by default), then for each environment the resource's exact name typed,
    # and for production "delete prod" as well. Only what the setup made, never a shared resource.
    Head 'Azure'
    $envFiles = @(Get-ChildItem (Join-Path $infra 'environments') -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { (Read-Json $_.FullName).names.$k })
    $deleted = 0
    $wanted = $false
    if (-not $envFiles.Count) { Note "no environment has $k (none made it yet): nothing to delete in Azure" }
    else {
        Note "Azure still has $k where an environment made it: $((@($envFiles | ForEach-Object { "$($_.BaseName) ($((Read-Json $_.FullName).names.$k))" })) -join ', ')."
        Note 'Deleting it there is DESTRUCTIVE and can''t be undone (its data goes with it). Keeping it costs what it costs.'
        $wanted = Confirm-Step "Delete $k from Azure as well? (destructive, can't be undone)" -DefaultNo -Danger
        if (-not $wanted) { Note "kept in Azure; delete it later by hand (az resource delete) or run this for another resource" }
    }
    $signedIn = $wanted -and (Get-Command az -ErrorAction SilentlyContinue) -and (Try-Az @('account', 'show'))
    if ($wanted -and -not $signedIn) { Note 'The Azure CLI is not signed in (az login): nothing is deleted; by hand:' }
    foreach ($f in @($envFiles | Where-Object { $wanted })) {
        $envAbbr = $f.BaseName
        $saved = Read-Json $f.FullName
        $name = [string]$saved.names.$k
        $group = [string]$saved.names.resourceGroup
        if ($saved.groups -and $saved.groups.$k) { Note "${envAbbr}: $name is shared from $($saved.groups.$k): kept (another environment or project uses it)"; continue }
        if (-not $signedIn) { Note "  ${envAbbr}: az resource delete -g $group -n $name --resource-type $($def.armType)   (check it first in the portal)"; continue }
        $script:subscription = $saved.subscriptionId
        $found = Find-MapResource $def $saved $hostKey
        if (-not $found) { Note "${envAbbr}: $name is not in Azure (any more)"; Remove-SavedName $f.FullName $saved $def; continue }
        if (-not $found.Ours) { Note "${envAbbr}: $name was not made by the setup (no managed-by tag): kept; delete it in the portal if you are sure"; continue }
        Say ''
        Say "    DELETE FROM AZURE: $($found.Type) $name in $($found.Group) ($envAbbr, $($naming.environments.$envAbbr)). This can't be undone." 'Red'
        if ($envAbbr -eq 'prod') { Say '    THIS IS PRODUCTION: whatever uses it there stops working.' 'Red' }
        if ($def.armType -eq 'Microsoft.Web/sites') { Note '  its managed identity''s role assignments go first' }
        if ($def.kind -eq 'keyVault') { Note '  a deleted vault stays recoverable for 30 days (asked: purge it)' }
        if (@('sqlDatabase', 'storage', 'storageQueue', 'serviceBus') -contains $def.kind) { Note '  ITS DATA GOES WITH IT (back it up first if you need it)' }
        $question = "To delete $name from $envAbbr, type its name exactly (anything else keeps it)"
        $typed = Read-Answer "  ${question}: " ([ordered]@{ kind = 'text'; question = $question; default = ''; danger = $true })
        if ($typed -cne $name) { Note "${envAbbr}: $name kept (the name didn't match)"; continue }
        if ($envAbbr -eq 'prod') {
            $question = 'Production: type "delete prod" to delete it (anything else keeps it)'
            $typed = Read-Answer "  ${question}: " ([ordered]@{ kind = 'text'; question = $question; default = ''; danger = $true })
            if ($typed -cne 'delete prod') { Note "${envAbbr}: $name kept"; continue }
        }
        Remove-MapResource $def $found
        Remove-SavedName $f.FullName $saved $def
        Ok "${envAbbr}: $name deleted"
        $deleted++
    }

    Head 'Next steps'
    Note 'Commit infra/ (the map, main.bicep, the environments'' saved answers).'
    if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 0; removed = $true; key = $k; deleted = $deleted }) }
    else { Write-Host ''; Write-Host "$k removed from the map." -ForegroundColor Green }
    return 0
}

# --- a new project (an empty instance) ---------------------------------------------------------------

# The map of a project without resources yet: the resource group and GitHub Actions' app registration,
# which every project has.
function New-BaseMap([string]$Name, [string]$Description, [string]$Region, [string]$Deployment) {
    $rg = Get-Filled (Get-Blueprint 'resourceGroup').entry (New-Placeholders 'resourceGroup' 'Resource group') @{}
    $deploy = Get-Filled (Get-Blueprint 'entraDeployApp').entry (New-Placeholders 'deployApp' 'App registration (Entra)') @{}
    return [pscustomobject][ordered]@{
        '$comment'  = "The map of this infrastructure (infra/README.md, 'The map'): every resource of one environment, and how it is named, asked, deployed, sized, priced, connected, checked and removed. infra/azure-setup.ps1 runs from it (-AddResource / -RemoveResource change it), infra/lazyazure.ps1 shows it, infra/generate.ps1 makes infra/main.bicep from it (never edit that)."
        project     = [pscustomobject][ordered]@{ name = $Name; description = $Description; setup = 'azure-setup.ps1'; template = 'main.bicep'; managedByTag = 'infra/main.bicep'; deploymentName = $Deployment; subscriptionMatch = '' }
        regions     = [pscustomobject][ordered]@{ default = $Region; staticWebApp = @('westeurope', 'eastus2', 'centralus', 'westus2', 'eastasia') }
        providers   = @()
        costExtras  = @('Custom domains, certificates, managed identities, app registration')
        resources   = @($rg, $deploy)
        domains     = @()
        domainNotes = [pscustomobject]@{}
        github      = [pscustomobject][ordered]@{
            variables    = [pscustomobject][ordered]@{ AZURE_CLIENT_ID = '{deployApp.appId}'; AZURE_TENANT_ID = '{tenant}'; AZURE_SUBSCRIPTION_ID = '{subscription}' }
            tokenSecrets = @()
            deployRoles  = @()
            push         = ''
            workflows    = @()
        }
        live        = @()
        cleanup     = @()
        connections = @()
        steps       = [pscustomobject][ordered]@{
            setup  = @('Environment', 'Azure CLI', 'Prefix', 'Region', 'Names', 'GitHub', 'Estimated monthly cost', '1. Azure resources', '2. GitHub -> Azure trust', '3. GitHub environment', '4. Custom domains', '5. Live', 'Next steps')
            remove = @('Environment', 'Azure CLI', 'What would be removed', 'Removing', 'Next steps')
        }
        removeOrder = @('microsoft.alertsmanagement/smartDetectorAlertRules', 'Microsoft.Web/certificates', 'Microsoft.Web/serverFarms', 'Microsoft.OperationalInsights/workspaces')
    }
}

# A new project: its name and prefix, then its resources from the catalog, one by one (or all of them
# from a spec file: -Init -SpecFile spec.json, see infra/README.md), then the map and main.bicep.
function Invoke-Init {
    Say 'New project: asks its name and prefix, then its resources from the catalog; writes infra.map.json and generates main.bicep. Nothing in Azure changes yet.' 'Cyan'
    if ($map) { throw 'infra/infra.map.json exists already: -AddResource adds to it (or move it away to start over).' }
    $script:namingChanged = $true
    $p = $null
    if ($SpecFile) {
        if (-not (Test-Path $SpecFile)) { throw "No spec file $SpecFile." }
        $script:specData = Read-Json (Resolve-Path $SpecFile).Path
        $script:auto = $true
        $p = $script:specData.project
        Note "from $SpecFile"
    }
    Head 'Project'
    $default = Split-Path $root -Leaf
    if ($p -and $p.name) { $default = $p.name }
    $name = Ask 'Project name' $default
    $default = "$name on Azure"
    if ($p -and $p.description) { $default = $p.description }
    $description = Ask 'One line about it' $default
    while ($true) {
        $default = [string]$naming.defaults.prefix
        if ($p -and $p.prefix) { $default = $p.prefix }
        $prefix = (Ask 'Prefix of every name (client-project, one part when they are the same)' $default).ToLower()
        if ($prefix -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { break }
        Note 'X lowercase letters and digits, parts separated by single hyphens'
    }
    $default = 'westeurope'
    if ($p -and $p.region) { $default = $p.region }
    $region = Ask 'Region' $default
    $default = $prefix.Split('-')[-1] + '-{env}'
    if ($p -and $p.deploymentName) { $default = $p.deploymentName }
    $deployment = Ask "Name of the deployments in Azure ({env} = the environment)" $default
    $script:map = New-BaseMap $name $description $region $deployment
    $script:defs = @($script:map.resources)
    $naming.defaults.prefix = $prefix

    Head 'Resources'
    $addable = @(Get-Blueprints | Where-Object { $_.addable } | Sort-Object kind)
    foreach ($b in $addable) { Note ("{0,-16} {1}" -f $b.kind, $b.about) }
    if ($script:specData) { foreach ($r in @($script:specData.resources)) { [void](Add-FromBlueprint ([string]$r.kind) $null $r) } }
    else {
        while ($true) {
            $default = 'done'
            if (@($map.resources).Count -le 2) { $default = 'appService' }
            Head 'Resources'
            Note ("in the map: " + ((@($map.resources | ForEach-Object { "$($_.key) ($($_.kind))" })) -join ', '))
            $k = Select-Option 'Add a resource (done = that is all)' (@($addable | ForEach-Object { $_.kind }) + 'done') $default
            if ($k -eq 'done') { break }
            [void](Add-FromBlueprint $k $null $null)
        }
    }
    $script:auto = $false

    Head 'Changes'
    foreach ($d in @($map.resources)) { Note ("{0,-16} {1} ({2})" -f $d.key, $d.title, $d.kind) }
    # A spec file is the answer to this too (it runs without questions).
    if (-not $script:specData -and -not (Confirm-Step 'Write infra/infra.map.json and naming.json and generate main.bicep?')) {
        Note 'nothing was written'
        if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = @(); code = 1; cancelled = $true }) }
        return 1
    }
    Save-Map
    Head 'Next steps'
    Note 'A dry run asks the names of every resource for an environment and shows what would be created:'
    Note '  .\infra\azure-setup.ps1 -DryRun     (or .\infra\lazyazure.ps1)'
    Note 'then a start creates it, the GitHub trust and the GitHub environment. Commit infra/.'
    $vars = @($map.github.variables.PSObject.Properties | Where-Object { $_.Name -notlike 'AZURE_*_ID' } | ForEach-Object { $_.Name })
    if ($vars.Count) { Note "The apps' deploy workflows use the GitHub environment's variables ($($vars -join ', '), AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID); add them to infra.map.json's github.workflows to have them named in the next steps." }
    $open = @($script:results | Where-Object { -not $_.Done } | ForEach-Object { $_.Text })
    if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = ''; ghEnv = ''; open = $open; code = [int][bool]$open.Count; added = $name }) }
    else { Write-Host ''; Write-Host "$name is set up in infra/infra.map.json." -ForegroundColor Green }
    return [int][bool]$open.Count
}

# --- the setup -------------------------------------------------------------------------------------

function Invoke-Setup {
    if (-not $script:replaying) {
        switch ($script:mode) {
            'dryrun' { Say 'Dry run: every question is asked, nothing is changed or saved.' 'Cyan' }
            'check' { Say 'Check: the saved answers, no questions, nothing is changed.' 'Cyan' }
            default { Say 'Start: every change is asked first.' 'Cyan' }
        }
        if ($script:mode -ne 'check') { Say "Enter accepts the value in brackets; '<' goes back to the previous question." 'Cyan' }
    }
    $script:res = [ordered]@{}
    $script:apps = @{}
    $script:choices = [ordered]@{}
    $script:vals = @{}
    $script:secrets = @{}
    $script:subs = [ordered]@{}
    $script:currentDef = $null

    Head 'Environment'
    $envs = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name })
    if ($script:mode -eq 'check') {
        # Only environments that are set up (have saved answers) can be checked.
        $envs = @($envs | Where-Object { Test-Path (Join-Path $infra "environments\$_.json") })
        if (-not $envs.Count) { throw 'No environment is set up yet (infra/environments/ is empty): run a dry run or start first.' }
    }
    foreach ($e in $envs) { Note ("{0,-5} {1}" -f $e, $naming.environments.$e) }
    if ($Environment -and $envs -contains $Environment) {
        $script:envAbbr = $Environment
        Note "environment: $Environment"
    } elseif ($script:mode -eq 'check' -and $envs.Count -eq 1) {
        $script:envAbbr = $envs[0]
        Note "environment: $($envs[0]) (the only one set up)"
    } else {
        $auto = $script:auto
        $script:auto = $false # the environment is asked in every mode (unless given)
        $script:envAbbr = Select-Option 'Environment' $envs $envs[0]
        $script:auto = $auto
    }
    $envAbbr = $script:envAbbr
    $ghEnv = [string]$naming.environments.$envAbbr # the GitHub environment (and the workflows' input)
    $script:vals['env'] = $envAbbr
    $script:vals['kvdns'] = '.vault.azure.net' # environment().suffixes.keyvaultDns in Azure's public cloud
    $script:vals['ghEnv'] = $ghEnv
    $envFile = Join-Path $infra "environments\$envAbbr.json"
    $script:saved = Read-Json $envFile
    $saved = $script:saved
    $script:fromCopy = $false # answers of another environment, not saved for this one yet
    $script:copyBranch = ''
    if ($script:ui) { Send ([ordered]@{ t = 'env'; env = $envAbbr; ghEnv = $ghEnv; saved = [bool]$saved }) }
    if ($saved) { Note "defaults from infra/environments/$envAbbr.json" } else { Note 'first run of this environment: defaults from infra/naming.json' }
    # A new environment can start from another one's answers (names moved to this environment), still
    # asking every question.
    if (-not $saved -and $script:mode -ne 'check') {
        $others = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { $_ -ne $envAbbr -and (Test-Path (Join-Path $infra "environments\$_.json")) })
        if ($others.Count) {
            $from = Select-Option 'Start from the answers of another environment (every question is still asked)' (@($others) + '-') $others[0]
            if ($from -ne '-') {
                $script:saved = Copy-Answers (Read-Json (Join-Path $infra "environments\$from.json")) $from $envAbbr
                $script:fromCopy = $true
                $saved = $script:saved
                Note "defaults from infra/environments/$from.json, moved to ${envAbbr}: names, custom domains and the deploy branch with $envAbbr instead of $from (each still asked); shared resources kept"
            }
        }
    }
    # Saved answers: keep them all (the default; each is shown in grey) or go through the questions.
    if ($saved -and -not $script:fromCopy -and $script:mode -ne 'check') {
        $change = (Read-Answer "  The answers of $envAbbr are saved. Change anything? [y/N] " ([ordered]@{ kind = 'confirm'; question = "The answers of $envAbbr are saved. Change anything?"; default = 'n' })).ToLower()
        $script:auto = -not $change.StartsWith('y')
        if ($script:auto) { Note 'keeping the saved answers' }
    }

    Head 'Azure CLI'
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'The Azure CLI is not installed: winget install Microsoft.AzureCLI, then a new terminal.' }
    $account = Try-Az @('account', 'show')
    if (-not $account) { throw 'The Azure CLI is not signed in: run  az login  and start again.' }
    Note "signed in as $($account.user.name)"
    $script:vals['me'] = [string]$account.user.name
    $subs = @(Invoke-Az @('account', 'list') | Where-Object { $_.state -eq 'Enabled' })
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $mark = ''
        if ($subs[$i].isDefault) { $mark = '  <- CLI default' }
        Note "$($i + 1). $($subs[$i].name) ($($subs[$i].id))$mark"
    }
    $guess = -1
    for ($i = 0; $i -lt $subs.Count; $i++) { if ($saved -and $subs[$i].id -eq $saved.subscriptionId) { $guess = $i } }
    if ($guess -lt 0 -and $map.project.subscriptionMatch) { for ($i = 0; $i -lt $subs.Count; $i++) { if ($guess -lt 0 -and $subs[$i].name -match $map.project.subscriptionMatch) { $guess = $i } } }
    if ($guess -lt 0) { for ($i = 0; $i -lt $subs.Count; $i++) { if ($subs[$i].isDefault) { $guess = $i } } }
    $n = 0
    if (-not [int]::TryParse((Ask 'Subscription (number)' ([string]($guess + 1))), [ref]$n) -or $n -lt 1 -or $n -gt $subs.Count) { throw 'No such subscription.' }
    $chosen = $subs[$n - 1]
    $script:subscription = $chosen.id
    $subscription = $chosen.id
    $tenant = $chosen.tenantId
    $script:vals['subscription'] = $subscription
    $script:vals['tenant'] = $tenant
    Ok "subscription $($chosen.name)"

    Head 'Prefix (infra/README.md, "Naming")'
    while ($true) {
        $default = [string]$naming.defaults.prefix
        if ($saved -and $saved.prefix) { $default = $saved.prefix }
        $script:prefix = (Ask 'Client-project prefix (one part when client and project are the same)' $default).ToLower()
        if ($script:prefix -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { break }
        Note 'X lowercase letters and digits, parts separated by single hyphens'
    }
    $script:samePrefix = $saved -and $saved.prefix -eq $script:prefix
    $project = $script:prefix

    Head 'Region'
    $rgDef = $defs | Where-Object { $_.ask -eq 'group' } | Select-Object -First 1
    $script:rgName = Read-Name $rgDef.label $rgDef.type (Get-Default $rgDef.key (Get-RuleName $rgDef.type))
    $rgName = $script:rgName
    $script:vals['rg'] = $rgName
    $rgExists = [bool](Invoke-Az @('group', 'exists', '-n', $rgName))
    if ($rgExists) {
        $location = (Invoke-Az @('group', 'show', '-n', $rgName)).location
    } else {
        $default = [string]$map.regions.default
        if ($saved -and $saved.location) { $default = $saved.location }
        $location = Ask 'Region' $default
    }
    $script:location = $location
    $state = 'new'
    if ($rgExists) { $state = 'exists' }
    Note "resource group ${rgName}: $state ($location)"
    Mark $rgDef.key $rgName $state ''
    $script:res[$rgDef.key] = [pscustomobject]@{ Name = $rgName; Group = ''; Found = $null }
    $hasStatic = [bool]@($defs | Where-Object { $_.armType -eq 'Microsoft.Web/staticSites' }).Count
    if (-not $hasStatic -or $staticLocations -contains $location) { $staticLocation = $location } else {
        $default = [string]$map.regions.default
        if ($saved -and $saved.staticLocation) { $default = $saved.staticLocation }
        $staticLocation = Select-Option 'Region of the Static Web App (offered in a few only)' $staticLocations $default
    }

    Head 'Names (Enter = the value in brackets)'
    foreach ($def in @($defs | Where-Object { $_.ask -ne 'group' })) { $script:res[$def.key] = Read-Resource $def }
    foreach ($dm in @($map.domains)) {
        $default = '-'
        if ($envAbbr -eq 'prod' -and $dm.prodDefault) { $default = $dm.prodDefault }
        if ($saved -and $saved.($dm.answer)) { $default = $saved.($dm.answer) }
        $script:choices[$dm.answer] = (Ask $dm.label $default).ToLower()
    }

    Head 'GitHub'
    $haveGh = $ghExe -and (Test-Gh @('auth', 'status'))
    $remote = $null
    $r = Invoke-Native 'git' @('-C', $root, 'remote', 'get-url', 'origin')
    if ($r.Code -eq 0 -and $r.Text -match 'github\.com[:/](.+?)(\.git)?$') { $remote = $Matches[1] }
    while ($true) {
        $default = $remote
        if ($saved -and $saved.repo) { $default = $saved.repo }
        $repo = Ask 'Repository (owner/name)' $default
        if ($repo -notmatch '^[\w.-]+/[\w.-]+$') { Note 'X owner/name' }
        elseif ($haveGh -and -not (Test-Gh @('api', "repos/$repo"))) { Note "X $repo not found (or no access with the GitHub CLI's account)" }
        else { break }
    }
    $script:vals['repo'] = $repo
    # The branch that deploys to this environment on every push (the workflows find it with
    # infra/route.ps1); the GitHub environment then only accepts deployments from it.
    while ($true) {
        $default = '-'
        if ($envAbbr -eq 'prod') { $default = 'production' }
        if ($saved -and $saved.branch) { $default = $saved.branch }
        $branch = Ask "Branch that deploys to $ghEnv ('-' = manual runs only)" $default
        if ($branch -eq '-' -or -not $haveGh -or (Test-Gh @('api', "repos/$repo/branches/$([uri]::EscapeDataString($branch))"))) { break }
        # Copied from another environment: a start can make the branch from that environment's (the same code).
        $base = ''
        if ($script:fromCopy -and $script:copyBranch -and $script:copyBranch -ne $branch -and (Test-Gh @('api', "repos/$repo/branches/$([uri]::EscapeDataString($script:copyBranch))"))) { $base = $script:copyBranch }
        if ($base -and -not $script:readOnly) {
            if (Confirm-Step "$repo has no branch ${branch}: create it from $base (the code $base deploys)?") {
                $sha = (Invoke-Gh @('api', "repos/$repo/branches/$([uri]::EscapeDataString($base))") -Json).commit.sha
                Invoke-Gh @('api', '-X', 'POST', "repos/$repo/git/refs", '-f', "ref=refs/heads/$branch", '-f', "sha=$sha") | Out-Null
                Ok "branch $branch created from $base"
                break
            }
        }
        if ($base) { Note "X $repo has no branch $branch yet (a start offers to create it from $base; or '-')" }
        else { Note "X $repo has no branch $branch (create it first, or '-')" }
        if ($script:readOnly) { break }
    }
    if ($branch -eq '-') { Note "GitHub environment $ghEnv, manual runs only" } else { Note "GitHub environment $ghEnv, deployed from $branch" }

    # The answers are the next run's defaults (compared as data, so another PowerShell's JSON layout
    # doesn't count as a change).
    $names = [ordered]@{}
    $groups = [ordered]@{}
    foreach ($def in $defs) {
        $res = $script:res[$def.key]
        if ($res.Name -or -not $def.optional) { $names[$def.key] = $res.Name }
        if ($def.groupParam) { $groups[$def.key] = $res.Group }
    }
    $answers = [ordered]@{
        subscriptionId = $subscription
        location       = $location
        staticLocation = $staticLocation
        prefix         = $script:prefix
        subs           = $script:subs
        repo           = $repo
        branch         = $branch
    }
    foreach ($k in $script:choices.Keys) { $answers[$k] = $script:choices[$k] }
    $answers.names = $names
    $answers.groups = $groups
    $answers = Get-OrderedLike $answers $saved
    Write-CostEstimate $location $staticLocation

    $newJson = ConvertTo-Json -InputObject $answers -Depth 10 -Compress
    $oldJson = ''
    if ($saved -and -not $script:fromCopy) { $oldJson = ConvertTo-Json -InputObject $saved -Depth 10 -Compress } # a copy is not saved yet
    if ($newJson -ne $oldJson) {
        if (Confirm-Step "Save these answers in infra/environments/$envAbbr.json?") {
            New-Item -ItemType Directory -Force -Path (Split-Path $envFile) | Out-Null
            [IO.File]::WriteAllText($envFile, (ConvertTo-Json -InputObject $answers -Depth 10) + "`n", $utf8)
            Note 'saved (commit it: the next run starts from it)'
            # The deploy workflows are triggered by the environments' branches: a new or changed one goes in.
            & (Join-Path $infra 'generate.ps1') -Check -Quiet
            if ($LASTEXITCODE -ne 0) {
                & (Join-Path $infra 'generate.ps1') -Quiet
                Note "the deploy workflows (.github/workflows) follow the environments' branches: regenerated, commit them too"
            }
            if ($script:ui) { Send ([ordered]@{ t = 'saved'; env = $envAbbr }) }
        }
    }
    $script:canGoBack = $false # changes start here
    if ($script:mode -ne 'check') { $script:auto = $false } # questions from here on (DNS) are asked again

    Head '1. Azure resources'
    foreach ($ns in @($map.providers)) {
        if ((Invoke-Az @('provider', 'show', '-n', $ns, '--query', 'registrationState')) -eq 'Registered') { continue }
        if (Confirm-Step "Register the resource provider $ns (once per subscription)?") {
            Invoke-Az @('provider', 'register', '-n', $ns, '--wait') | Out-Null
            Ok "$ns registered"
        } else { Missing "resource provider $ns not registered" }
    }

    $haveRg = $rgExists
    if ($haveRg) { Ok "resource group $rgName ($location)" }
    elseif (Confirm-Step "Create the resource group $rgName in $location?") {
        Invoke-Az @('group', 'create', '-n', $rgName, '-l', $location, '--tags', "project=$project", "environment=$ghEnv") | Out-Null
        $haveRg = $true
        Ok "resource group $rgName created ($location)"
        Mark $rgDef.key $rgName 'created' ''
    } else { Missing "resource group $rgName" }

    $templatePending = $false
    $appDefs = @($defs | Where-Object { $appTypes -contains $_.armType })
    if ($haveRg) {
        foreach ($def in $appDefs) { if ($script:res[$def.key].Found) { $script:apps[$def.key] = Get-App $def.key } }
        $changes = @()
        $later = @()

        # The secrets the setup keeps (the map's "by": "setup", e.g. a secret two apps share) keep their value:
        # the app setting that mirrors it (readable with the management rights the setup needs anyway), else
        # the vault's; a new one only when neither has it. It is written to the vault only when missing there
        # or different, since every write is a new version.
        $secretParams = [ordered]@{}
        foreach ($vdef in @($defs | Where-Object { $_.secrets })) {
            $vres = $script:res[$vdef.key]
            $vaultGroup = $rgName
            if ($vres.Group) { $vaultGroup = $vres.Group }
            $vaultId = "/subscriptions/$subscription/resourceGroups/$vaultGroup/providers/$($vdef.armType)/$($vres.Name)"
            if ($vres.Found) { $vaultId = $vres.Found.id }
            foreach ($sec in @($vdef.secrets | Where-Object { $_.by -eq 'setup' })) {
                $inVault = [bool](Try-Az @('resource', 'show', '--ids', "$vaultId/secrets/$($sec.name)"))
                $fromVault = $null
                if ($inVault) { $fromVault = Try-Az @('keyvault', 'secret', 'show', '--vault-name', $vres.Name, '--name', $sec.name, '--query', 'value') }
                $fromMirror = $null
                if ($sec.mirror -and $script:res[$sec.mirror.resource].Found) { $fromMirror = (Get-AppSettings $sec.mirror.resource)[$sec.mirror.setting] }
                $kept = $fromMirror
                if (-not $kept) { $kept = $fromVault }
                $writeSecret = (-not $inVault) -or (-not $kept) -or ($fromVault -and $fromVault -ne $kept)
                $secret = $kept
                if (-not $secret) { $secret = New-Secret }
                $script:secrets[$sec.name] = $secret
                $secretParams[$sec.param] = $secret
                $secretParams[$sec.writeParam] = [bool]$writeSecret
                if ($writeSecret -and $inVault) { $later += [pscustomobject]@{ changeType = 'Modify'; resourceId = "/providers/$($vdef.armType)/$($vres.Name)/secrets/$($sec.name)" } }
            }
        }
        $me = Try-Az @('ad', 'signed-in-user', 'show')
        $ownerId = ''
        if ($me) { $ownerId = $me.id }

        # main.bicep's parameters: the map's param / groupParam / size, the domains, the secrets.
        $params = [ordered]@{
            location        = $location
            staticLocation  = $staticLocation
            environmentName = $ghEnv
            project         = $project
        }
        foreach ($def in $defs) {
            $res = $script:res[$def.key]
            if ($def.param) { $params[$def.param] = $res.Name }
            if ($def.groupParam) { $params[$def.groupParam] = $res.Group }
            if ($def.size) { $params[$def.size.param] = $script:choices[$def.size.answer] }
            if ($def.admin) {
                $admin = ([string]$script:choices[$def.admin.answer]).Split('|')
                $type = 'User'
                if ($admin[0]) { $type = $admin[0] }
                $params[$def.admin.typeParam] = $type
                $params[$def.admin.loginParam] = [string]($admin | Select-Object -Skip 1 -First 1)
                $params[$def.admin.sidParam] = [string]($admin | Select-Object -Skip 2 -First 1)
            }
        }
        foreach ($dm in @($map.domains | Where-Object { $_.param })) {
            $value = [string]$script:choices[$dm.answer]
            if ($value -eq '-') { $value = '' }
            $params[$dm.param] = $value
        }
        $params.ownerObjectId = $ownerId
        foreach ($k in $secretParams.Keys) { $params[$k] = $secretParams[$k] }
        $parameters = [ordered]@{}
        # Only what main.bicep declares (a project without a Static Web App or a vault has no staticLocation or
        # ownerObjectId; Azure refuses parameters a template doesn't have).
        $declared = @([regex]::Matches((Get-Content (Join-Path $infra $map.project.template) -Raw), '(?m)^param\s+(\w+)') | ForEach-Object { $_.Groups[1].Value })
        foreach ($k in $params.Keys) { if ($declared -contains $k) { $parameters[$k] = @{ value = $params[$k] } } }
        $paramsFile = Write-TempJson 'parameters.json' ([ordered]@{
                '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
                contentVersion = '1.0.0.0'
                parameters     = $parameters
            })
        $deploymentName = ([string]$map.project.deploymentName).Replace('{env}', $envAbbr)
        $deployment = @('-g', $rgName, '-n', $deploymentName, '-f', (Join-Path $infra $map.project.template), '-p', "@$paramsFile")
        # main.bicep is made from the map (infra/generate.ps1): an older one would deploy something else.
        & (Join-Path $infra 'generate.ps1') -Check -Quiet
        if ($LASTEXITCODE -ne 0) { Missing "infra/$($map.project.template) or the deploy workflows aren't what infra.map.json makes: run .\infra\generate.ps1 first" }
        Note "comparing Azure with the template (what-if)..."
        $whatIf = Invoke-Az (@('deployment', 'group', 'what-if') + $deployment + @('--no-pretty-print'))
        $changes = @($whatIf.changes | Where-Object { Test-RealChange $_ })
        # The app settings what-if can't read: checked directly against the map's "appSettings" (every
        # setting there; the values the map expects where they are known here).
        foreach ($def in @($defs | Where-Object { $_.appSettings })) {
            if (-not $script:res[$def.key].Found) { continue }
            if ($def.armType -eq 'Microsoft.Web/sites' -and -not $script:apps[$def.key]) { continue }
            $have = Get-AppSettings $def.key
            $wrong = @()
            foreach ($s in @($def.appSettings)) {
                $value = $have[$s.name]
                # value: the whole setting; prefix: how it starts (never $s.equals: that is the object's method)
                $expect = [string]$s.value
                if (-not $expect) { $expect = [string]$s.prefix }
                if (-not $expect) { if (-not $value) { $wrong += $s.name }; continue }
                $expected = Expand $expect
                if ($null -eq $expected) { if ($s.unknown -eq 'wrong' -or -not $value) { $wrong += $s.name }; continue }
                if ($s.value -and $value -ne $expected) { $wrong += $s.name }
                elseif ($s.prefix -and (-not $value -or -not $value.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase))) { $wrong += $s.name }
            }
            $wrong = @($wrong | Select-Object -Unique)
            if ($wrong.Count) { $changes += [pscustomobject]@{ changeType = 'Modify'; resourceId = "/providers/$($def.armType)/$($script:res[$def.key].Name)/config/appsettings ($($wrong -join ', '))" } }
        }
        $changes += $later
        if (-not $changes.Count) { Ok "resources match infra/$($map.project.template)" }
        else {
            foreach ($c in $changes) { Note ("{0,-8} {1}" -f $c.changeType, ($c.resourceId -split '/providers/')[-1]) }
            # The custom domains need DNS records pointing to what this creates: the instructions now, so
            # they can be added while it deploys (step 4 checks them and adds the domains).
            if (@($map.domains | Where-Object { $script:choices[$_.answer] -ne '-' -and -not $script:res[$_.resource].Found }).Count) {
                Write-DnsInstructions 'DNS for the custom domains (add it once these are created; the rest of the values follow after the deployment):' (Get-DnsRecords)
            }
            $plural = ''
            if ($changes.Count -gt 1) { $plural = 's' }
            if (Confirm-Step "Deploy infra/$($map.project.template) ($($changes.Count) change$plural, a few minutes)?") {
                Invoke-Az (@('deployment', 'group', 'create') + $deployment) | Out-Null
                Ok "infra/$($map.project.template) deployed"
                foreach ($def in $defs) { $res = $script:res[$def.key]; if ($res.Name -and -not $res.Group -and -not $res.Found -and $def.ask -ne 'name' -and $def.ask -ne 'group') { Mark $def.key $res.Name 'created' '' } }
            } else { Missing "resources differ from the template ($($changes.Count) changes)"; $templatePending = $true }
        }
        foreach ($def in $appDefs) { $script:apps[$def.key] = Get-App $def.key }
        # Just created: now every value is known.
        if ($changes.Count -and @($map.domains | Where-Object { $script:choices[$_.answer] -ne '-' -and -not $script:res[$_.resource].Found -and $script:apps[$_.resource] }).Count) {
            Write-DnsInstructions 'DNS for the custom domains, all values (step 4 checks it and adds the domains):' (Get-DnsRecords)
        }
    }

    # The apps' database users (the map's "sql" connections).
    $sqlLinks = @($map.connections | Where-Object { $_.kind -eq 'sql' })
    if ($sqlLinks.Count) {
        Head 'Database access'
        try { foreach ($c in $sqlLinks) { Grant-DatabaseUser $c } } finally { Close-SqlFirewall }
    }

    Head '2. GitHub -> Azure trust (OIDC)'
    $deployDef = $defs | Where-Object { $_.ask -eq 'name' -and $_.type -eq 'deploy' } | Select-Object -First 1
    $deployApp = $script:res[$deployDef.key].Name
    $entra = @(Invoke-Az @('ad', 'app', 'list', '--display-name', $deployApp)) | Where-Object { $_ } | Select-Object -First 1
    if ($entra) { Ok "app registration $deployApp ($($entra.appId))"; Mark $deployDef.key $deployApp 'ours' '' }
    elseif (Confirm-Step "Create the app registration $deployApp (GitHub Actions signs in as it)?") {
        $entra = Invoke-Az @('ad', 'app', 'create', '--display-name', $deployApp)
        Ok "app registration $deployApp created ($($entra.appId))"
        Mark $deployDef.key $deployApp 'created' ''
    } else { Missing "app registration $deployApp"; Mark $deployDef.key $deployApp 'new' '' }
    if ($entra) { $script:vals["$($deployDef.key).appId"] = $entra.appId }

    $principal = $null
    if ($entra) {
        $principal = Try-Az @('ad', 'sp', 'show', '--id', $entra.appId)
        if ($principal) { Ok 'service principal' }
        elseif (Confirm-Step 'Create its service principal?') {
            $principal = Invoke-Az @('ad', 'sp', 'create', '--id', $entra.appId)
            Ok 'service principal created'
        } else { Missing 'service principal' }

        # The subject GitHub puts in its token: with immutable ids ('repo:owner@123/name@456:...') when the
        # repository uses them (seen on the first deploy: AADSTS700213 with the name-only one), else
        # 'repo:owner/name:...'. GitHub reports its prefix; both forms are trusted, so either works.
        $subjects = @("repo:${repo}:environment:$ghEnv")
        if ($haveGh) {
            $oidc = Try-Gh @('api', "repos/$repo/actions/oidc/customization/sub") -Json
            if ($oidc -and $oidc.sub_claim_prefix -and "$($oidc.sub_claim_prefix):environment:$ghEnv" -ne $subjects[0]) { $subjects += "$($oidc.sub_claim_prefix):environment:$ghEnv" }
        } else { Note "without the GitHub CLI only the name-based subject is known; if the deploy's Azure login fails with AADSTS700213, add the subject it names here" }
        $existing = @(Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $entra.appId)) | Where-Object { $_ }
        for ($i = 0; $i -lt $subjects.Count; $i++) {
            $subject = $subjects[$i]
            $credentialName = "github-$ghEnv"
            if ($i -gt 0) { $credentialName = "github-$ghEnv-ids" }
            if (@($existing | Where-Object { $_.subject -eq $subject }).Count) { Ok "federated credential $subject" }
            elseif (Confirm-Step "Trust GitHub Actions of $repo, environment $ghEnv ($subject)?") {
                $credential = Write-TempJson 'credential.json' ([ordered]@{ name = $credentialName; issuer = 'https://token.actions.githubusercontent.com'; subject = $subject; audiences = @('api://AzureADTokenExchange') })
                Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $entra.appId, '--parameters', "@$credential") | Out-Null
                Ok "federated credential $subject created"
            } else { Missing "federated credential $subject" }
        }
    }

    # The role GitHub Actions' app registration needs on each app it deploys (the map's deployRoles).
    foreach ($deployRole in @($map.github.deployRoles)) {
        $roleTarget = $script:apps[$deployRole.resource]
        $roleTargetName = $script:res[$deployRole.resource].Name
        if (-not ($principal -and $roleTarget)) { continue }
        $role = [string]$deployRole.role
        if (@(Invoke-Az @('role', 'assignment', 'list', '--assignee', $principal.id, '--scope', $roleTarget.id, '--role', $role)) | Where-Object { $_ }) { Ok "$role on $roleTargetName" }
        elseif (Confirm-Step "Let $deployApp deploy to $roleTargetName ($role)?") {
            Invoke-Az @('role', 'assignment', 'create', '--assignee-object-id', $principal.id, '--assignee-principal-type', 'ServicePrincipal', '--role', $role, '--scope', $roleTarget.id) | Out-Null
            Ok "$role on $roleTargetName assigned"
        } else { Missing "$role on $roleTargetName" }
    }

    Head "3. GitHub environment $ghEnv"
    $vars = [ordered]@{}
    foreach ($p in $map.github.variables.PSObject.Properties) { $vars[$p.Name] = Expand $p.Value }
    # Each Static Web App's deployment token, as a secret of the GitHub environment (the map's tokenSecrets).
    $tokens = @(foreach ($t in @($map.github.tokenSecrets)) {
            $app = $script:res[$t.resource]
            $value = $null
            if ($script:apps[$t.resource]) {
                $secrets = Try-Az @('staticwebapp', 'secrets', 'list', '-g', $rgName, '-n', $app.Name)
                if ($secrets) { $value = $secrets.properties.apiKey }
            }
            [pscustomobject]@{ Name = [string]$t.name; App = $app.Name; Existed = [bool]$app.Found; Token = $value }
        })
    if ($haveGh) {
        $haveEnv = Test-Gh @('api', "repos/$repo/environments/$ghEnv")
        if ($haveEnv) { Ok "environment $ghEnv" }
        elseif (Confirm-Step "Create the GitHub environment ${ghEnv}?") {
            Invoke-Gh @('api', '-X', 'PUT', "repos/$repo/environments/$ghEnv") | Out-Null
            $haveEnv = $true
            Ok "environment $ghEnv created"
        } else { Missing "GitHub environment $ghEnv" }
        if ($haveEnv) {
            # Deployment branches: only the environment's branch, or any branch for manual-only environments.
            $envInfo = Try-Gh @('api', "repos/$repo/environments/$ghEnv") -Json
            $policyList = Try-Gh @('api', "repos/$repo/environments/$ghEnv/deployment-branch-policies") -Json
            $policies = @()
            if ($policyList) { $policies = @($policyList.branch_policies | Where-Object { $_ }) }
            $policyNames = @($policies | ForEach-Object { $_.name })
            $custom = $envInfo -and $envInfo.deployment_branch_policy -and $envInfo.deployment_branch_policy.custom_branch_policies
            if ($branch -eq '-') {
                if (-not ($envInfo -and $envInfo.deployment_branch_policy)) { Ok "${ghEnv}: any branch can deploy (manual runs)" }
                elseif (Confirm-Step "Let any branch deploy to $ghEnv (now: $($policyNames -join ', '))?") {
                    Invoke-Gh @('api', '-X', 'PUT', "repos/$repo/environments/$ghEnv", '--input', (Write-TempJson 'env.json' @{ deployment_branch_policy = $null })) | Out-Null
                    Ok "${ghEnv}: any branch can deploy"
                } else { Missing "${ghEnv}: deployment branches" }
            } elseif ($custom -and $policyNames.Count -eq 1 -and $policyNames[0] -eq $branch) { Ok "${ghEnv}: deployed only from $branch" }
            elseif (Confirm-Step "Allow only $branch to deploy to $ghEnv$(if ($policyNames.Count) { " (now: $($policyNames -join ', '))" })?") {
                Invoke-Gh @('api', '-X', 'PUT', "repos/$repo/environments/$ghEnv", '--input', (Write-TempJson 'env.json' @{ deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true } })) | Out-Null
                foreach ($p in $policies) { if ($p.name -ne $branch) { Invoke-Gh @('api', '-X', 'DELETE', "repos/$repo/environments/$ghEnv/deployment-branch-policies/$($p.id)") | Out-Null } }
                if ($policyNames -notcontains $branch) { Invoke-Gh @('api', '-X', 'POST', "repos/$repo/environments/$ghEnv/deployment-branch-policies", '-f', "name=$branch", '-f', 'type=branch') | Out-Null }
                Ok "${ghEnv}: deployed only from $branch"
            } else { Missing "${ghEnv}: deployment branch $branch" }

            $have = @{}
            foreach ($v in @(Try-Gh @('variable', 'list', '--repo', $repo, '--env', $ghEnv, '--json', 'name,value') -Json)) { if ($v) { $have[$v.name] = $v.value } }
            foreach ($name in $vars.Keys) {
                $value = $vars[$name]
                if (-not $value) { Missing "${name}: no value yet" }
                elseif ($have[$name] -eq $value) { Ok "$name = $value" }
                elseif (Confirm-Step "Set $name = $value$(if ($have[$name]) { " (now $($have[$name]))" })?") {
                    Invoke-Gh @('variable', 'set', $name, '--repo', $repo, '--env', $ghEnv, '--body', $value) | Out-Null
                    Ok "$name = $value set"
                } else { Missing $name }
            }

            # A secret can't be read back: set when missing or when the web app is new (a new token), else
            # kept (-RefreshToken sets it again, e.g. after resetting the token in the portal).
            $envSecrets = @(Try-Gh @('secret', 'list', '--repo', $repo, '--env', $ghEnv, '--json', 'name') -Json)
            foreach ($t in $tokens) {
                $present = [bool](@($envSecrets | Where-Object { $_ -and $_.name -eq $t.Name }).Count)
                if (-not $t.Token) { Missing "$($t.Name): the static web app comes first" }
                elseif ($present -and $t.Existed -and -not $RefreshToken) { Ok "$($t.Name) (present)" }
                else {
                    $verb = 'Set'
                    if ($present) { $verb = 'Replace' }
                    $why = ''
                    if ($present -and -not $t.Existed) { $why = ' (the Static Web App is new)' }
                    if (Confirm-Step "$verb $($t.Name) from $($t.App)$why?") {
                        Invoke-Gh @('secret', 'set', $t.Name, '--repo', $repo, '--env', $ghEnv, '--body', $t.Token) | Out-Null
                        Ok "$($t.Name) set"
                    } else { Missing $t.Name }
                }
            }
        }
    } else {
        Note 'The GitHub CLI is not installed or not signed in (winget install GitHub.cli, gh auth login, then run'
        Note "this again to set and check them), so by hand: an environment named $ghEnv"
        Note "(https://github.com/$repo/settings/environments) with these variables:"
        foreach ($name in $vars.Keys) {
            $value = $vars[$name]
            if (-not $value) { $value = '(after step 2)' }
            Note ("  {0,-22} {1}" -f $name, $value)
        }
        if ($branch -ne '-') { Note "deployment branches: selected branches, only $branch" }
        foreach ($t in $tokens) {
            if ($t.Token) { Note "and the secret $($t.Name) = az staticwebapp secrets list -g $rgName -n $($t.App) --query properties.apiKey" }
            else { Note "and the secret $($t.Name) (after step 1)" }
        }
        Missing "GitHub environment $ghEnv not checked (no GitHub CLI)"
    }

    Head '4. Custom domains'
    $script:domainReady = @{}
    $script:domainsToAdd = $false # DNS is there, the domain not added yet (a dry run or check doesn't add it)
    foreach ($dm in @($map.domains)) {
        $domain = [string]$script:choices[$dm.answer]
        if ($domain -eq '-') { Note "$($dm.what): none"; continue }
        if ($dm.dns -eq 'staticWebApp') { Add-StaticDomain $dm $domain }
        elseif ($dm.dns -eq 'appService') { Add-AppServiceDomain $dm $domain }
    }

    Head '5. Live'
    $allLive = $true
    foreach ($lv in @($map.live)) {
        $app = $script:apps[$lv.resource]
        $live = $false
        if (-not $app) { Missing "$($lv.what): not created yet"; $allLive = $false; continue }
        $bases = @("https://$($app.defaultHostName)")
        if ($lv.domain -and $script:domainReady[$lv.domain]) { $bases += "https://$($script:choices[$lv.domain])" }
        foreach ($base in $bases) {
            if ($lv.kind -eq 'health') {
                $health = Get-Url "$base$($lv.path)"
                $version = ''
                if ($lv.version) {
                    $version = (Get-Url "$base$($lv.version)").Text
                    try { $v = ($version | ConvertFrom-Json).version; if ($v) { $version = $v } } catch { }
                }
                if ($health.Text.Trim() -eq $lv.expect) { Ok "${base}: $($lv.expect), $version"; $live = $true }
                else {
                    $text = $health.Text
                    if ($text.Length -gt 60) { $text = $text.Substring(0, 60) }
                    Missing "$base$($lv.path): $($health.Status) $text (not deployed yet? $($lv.workflow), environment $ghEnv)"
                }
            } else {
                $page = Get-Url "$base$($lv.path)"
                if ($page.Status -eq 200 -and $page.Text -match $lv.match) { Ok "${base}: the $($lv.what)"; $live = $true }
                elseif ($page.Status -eq 200) { Missing "${base}: the Azure placeholder (not deployed yet? $($lv.workflow))" }
                else { Missing "${base}: $($page.Status) $($page.Text)" }
            }
        }
        if (-not $live) { $allLive = $false }
    }

    # Everything still to do by hand, step by step: where, and what. Only the steps that apply now.
    $steps = New-Object System.Collections.ArrayList
    function Add-Step([string]$Title, [string]$Where, [string[]]$What) { [void]$steps.Add([ordered]@{ title = $Title; where = $Where; what = @($What) }) }
    $created = -not @($appDefs | Where-Object { -not $script:apps[$_.key] }).Count
    if (-not $created) {
        $how = 'Run this again and choose 3. Start'
        if ($script:mode -eq 'start') { $how = 'Run this again and say yes to the deployment' }
        Add-Step 'Create the resources' 'this PowerShell window (repository root)' @("$how`: .\infra\azure-setup.ps1 -Start -Environment $envAbbr; the steps below follow.")
    } elseif ($templatePending) {
        Add-Step 'Apply the template changes' 'this PowerShell window (repository root)' @(
            ".\infra\azure-setup.ps1 -Start -Environment $envAbbr, keep the saved answers, and say yes to the deployment",
            '(step 1 lists what changes).')
    }
    $answersChanged = (Invoke-Native 'git' @('-C', $root, 'status', '--porcelain', '--', "infra/environments/$envAbbr.json")).Text
    if ($answersChanged) {
        $pushTo = 'any; this environment deploys by manual runs'
        if ($branch -ne '-') { $pushTo = $branch }
        Add-Step 'Commit the saved answers' 'git, in the repository' @(
            "git add infra/environments/$envAbbr.json",
            "git commit -m `"Azure environment $envAbbr`"",
            "then push it to the branch that deploys ($pushTo): the workflows read it to find the environment.")
    }
    if (-not $haveGh) {
        $lines = @()
        if ($branch -ne '-') { $lines += "Deployment branches and tags: Selected branches -> Add rule: $branch" }
        $lines += 'Environment variables -> Add variable, for each:'
        foreach ($name in $vars.Keys) {
            $value = $vars[$name]
            if (-not $value) { $value = '(after step 2 of this script: run it again)' }
            $lines += ("  {0,-22} {1}" -f $name, $value)
        }
        foreach ($t in $tokens) {
            $lines += "Environment secrets -> Add secret: $($t.Name), the value of"
            $lines += "  az staticwebapp secrets list -g $rgName -n $($t.App) --query properties.apiKey -o tsv"
        }
        Add-Step "Set up the GitHub environment $ghEnv" "https://github.com/$repo/settings/environments (New environment: $ghEnv)" $lines
    }
    $records = @($script:dnsTodo)
    if (-not $records.Count -and @($map.domains | Where-Object { $script:choices[$_.answer] -ne '-' -and -not $script:apps[$_.resource] }).Count) { $records = @(Get-DnsRecords) }
    if ($records.Count) {
        $zones = (@($records | ForEach-Object { Get-Zone $_.Name }) | Select-Object -Unique) -join ', '
        $lines = @()
        foreach ($r in $records) {
            $how = 'pointing to'
            if ($r.Type -eq 'TXT') { $how = 'with the value' }
            $lines += ("{0,-5}  {1,-30} {2,-14} {3}" -f $r.Type, (Get-RelativeName $r.Name), $how, $r.Value)
        }
        $lines += 'Then run this again: step 4 checks the records and adds the domains with their certificates.'
        if ($map.domainNotes -and $map.domainNotes.$envAbbr) { $lines += @($map.domainNotes.$envAbbr) }
        Add-Step 'Add the DNS records of the custom domains' "the DNS host of $zones (where the domain's DNS is managed)" $lines
    }
    if ($script:domainsToAdd) {
        Add-Step 'Add the custom domains' 'this PowerShell window (repository root)' @(
            "The DNS records are there. Run .\infra\azure-setup.ps1 -Start -Environment $envAbbr and say yes in step 4:",
            'it adds the domains to the apps with their free certificates (a Static Web App''s takes a few minutes).')
    }
    if ($created -and -not $allLive) {
        $lines = @()
        $push = ''
        if ($map.github.push) { $push = " ($($map.github.push))" }
        if ($branch -ne '-') { $lines += "Push to $branch$push, or:" }
        $flows = @($map.github.workflows | Where-Object { $_ })
        if ($flows.Count) {
            $run = "Actions -> `"$($flows[0])`" -> Run workflow -> environment $ghEnv"
            foreach ($f in @($flows | Select-Object -Skip 1)) { $run += ", and the same for `"$f`"" }
            $lines += "$run."
        } else { $lines += "Actions -> run the workflow of each app with the environment $ghEnv (they sign in with AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)." }
        $both = 'every app'
        if ($flows.Count -eq 2) { $both = 'both' }
        $lines += "Then run this again with -Check: step 5 shows $both live."
        Add-Step 'Deploy the apps' "https://github.com/$repo/actions" $lines
    }
    foreach ($c in @($map.cleanup)) {
        if (-not $c -or $c.env -ne $envAbbr -or -not $haveGh -or -not $created -or -not $allLive) { continue }
        if (-not (Test-Gh @('secret', 'list', '--repo', $repo)) -or -not ((Invoke-Gh @('secret', 'list', '--repo', $repo)) -match $c.repoSecret)) { continue }
        Add-Step $c.title $c.where @($c.what | ForEach-Object { Expand $_ })
    }
    # The secrets put in by hand (e.g. API keys of other services): the app's settings already point at them
    # (main.bicep); until they are there the app treats them as not set.
    foreach ($vdef in @($defs | Where-Object { $_.handSecrets })) {
        $hs = $vdef.handSecrets
        if (-not $script:apps[$hs.restart]) { continue }
        $vres = $script:res[$vdef.key]
        $vaultGroupName = $rgName
        if ($vres.Group) { $vaultGroupName = $vres.Group }
        $vaultResource = "/subscriptions/$subscription/resourceGroups/$vaultGroupName/providers/$($vdef.armType)/$($vres.Name)"
        $missingKeys = @($vdef.secrets | Where-Object { $_.by -eq 'hand' -and -not (Try-Az @('resource', 'show', '--ids', "$vaultResource/secrets/$($_.name)")) })
        if (-not $missingKeys.Count) { continue }
        $lines = @()
        foreach ($k in $missingKeys) {
            $placeholder = '"<' + $k.label + '>"'
            $lines += "az keyvault secret set --vault-name $($vres.Name) --name $($k.name) --value $placeholder"
            $lines += "  $($k.what); $($hs.reader) reads it as $($k.setting)"
        }
        $lines += "az webapp restart -g $rgName -n $($script:res[$hs.restart].Name)"
        $lines += "  $($hs.reader) reads Key Vault references when it starts (portal: $($hs.reader) -> Environment variables -> Pull reference values)"
        if ($hs.after) { $lines += $hs.after }
        Add-Step (Expand $hs.title) $hs.where $lines
    }
    if ($steps.Count) {
        Head 'Next steps (by hand)'
        if ($script:ui) { Send ([ordered]@{ t = 'steps'; items = @($steps) }) }
        else {
            for ($i = 0; $i -lt $steps.Count; $i++) {
                Write-Host ''
                Write-Host "  $($i + 1). $($steps[$i].title)" -ForegroundColor Cyan
                Write-Host "       Where: $($steps[$i].where)"
                Write-Host '       What:'
                foreach ($line in $steps[$i].what) { Write-Host "         $line" }
            }
        }
    }

    $open = @($script:results | Where-Object { -not $_.Done })
    $code = 0
    if ($open.Count) { $code = 1 }
    if ($script:ui) {
        Send ([ordered]@{ t = 'summary'; env = $envAbbr; ghEnv = $ghEnv; open = @($open | ForEach-Object { $_.Text }); code = $code })
        return $code
    }
    Write-Host ''
    if ($open.Count) {
        Write-Host "$envAbbr ($ghEnv): $($open.Count) open:" -ForegroundColor Yellow
        foreach ($o in $open) { Write-Host "  -- $($o.Text)" -ForegroundColor Yellow }
        return 1
    }
    Write-Host "$envAbbr ($ghEnv): everything is set up." -ForegroundColor Green
    return 0
}

# --- remove ------------------------------------------------------------------------------------------

# Removes what the setup created for one environment, from its saved answers: the resources the template
# made (tag managed-by) and the ones Azure or the setup added for them (an App Service's managed
# certificate, Application Insights' "Failure Anomalies" alert rule), the resource group when nothing else
# is in it, the app registration GitHub Actions deployed with, and the GitHub environment. Kept: shared
# resources from other resource groups, anything else in the group, the DNS records (listed for you).
# Everything is shown first and confirmed by typing the resource group's name.
function Invoke-Remove {
    Say 'Remove all: deletes everything the setup created for an environment; everything is shown first.' 'Cyan'

    Head 'Environment'
    $envs = @($naming.environments.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { Test-Path (Join-Path $infra "environments\$_.json") })
    if (-not $envs.Count) { throw 'No environment is set up (infra/environments/ is empty): nothing to remove.' }
    foreach ($e in $envs) { Note ("{0,-5} {1}" -f $e, $naming.environments.$e) }
    if ($Environment -and $envs -contains $Environment) { $envAbbr = $Environment; Note "environment: $Environment" }
    else { $envAbbr = Select-Option 'Environment to remove' $envs $envs[0] }
    $ghEnv = [string]$naming.environments.$envAbbr
    if ($script:ui) { Send ([ordered]@{ t = 'env'; env = $envAbbr; ghEnv = $ghEnv; saved = $true }) }
    $envFile = Join-Path $infra "environments\$envAbbr.json"
    $saved = Read-Json $envFile
    $rgDef = $defs | Where-Object { $_.ask -eq 'group' } | Select-Object -First 1
    $rgName = [string]$saved.names.($rgDef.key)

    Head 'Azure CLI'
    if (-not (Try-Az @('account', 'show'))) { throw 'The Azure CLI is not signed in: run  az login  and start again.' }
    $sub = @(Invoke-Az @('account', 'list') | Where-Object { $_ -and $_.id -eq $saved.subscriptionId })
    if (-not $sub.Count) { throw "This account can't see the environment's subscription $($saved.subscriptionId) (az login with the right account or tenant)." }
    $script:subscription = $saved.subscriptionId
    Ok "subscription $($sub[0].name)"

    # What is there, and what is ours.
    $certDomains = @($map.domains | Where-Object { $_.dns -eq 'appService' } | ForEach-Object { [string]$saved.($_.answer) } | Where-Object { $_ -and $_ -ne '-' })
    $insightsNames = @($defs | Where-Object { $_.armType -eq 'Microsoft.Insights/components' } | ForEach-Object { $saved.names.($_.key) } | Where-Object { $_ })
    $resources = @()
    if (Invoke-Az @('group', 'exists', '-n', $rgName)) { $resources = @(Invoke-Az @('resource', 'list', '-g', $rgName) | Where-Object { $_ }) }
    # A SQL server's system database goes with its server.
    $resources = @($resources | Where-Object { -not ($_.type -ieq 'Microsoft.Sql/servers/databases' -and $_.name -like '*/master') })
    $ours = @(); $others = @()
    foreach ($r in $resources) {
        $isOurs = $r.tags -and $r.tags.'managed-by' -eq $managedBy
        if (-not $isOurs -and $r.type -eq 'Microsoft.Web/certificates' -and @($certDomains | Where-Object { $r.name -ieq $_ }).Count) { $isOurs = $true }
        if (-not $isOurs -and $r.type -ieq 'microsoft.alertsmanagement/smartDetectorAlertRules' -and @($insightsNames | Where-Object { $r.name -eq "Failure Anomalies - $_" }).Count) { $isOurs = $true }
        if ($isOurs) { $ours += $r } else { $others += $r }
    }
    foreach ($def in $defs) {
        $name = [string]$saved.names.($def.key)
        if (-not $name) { continue }
        $state = 'gone'
        if ($saved.groups -and $saved.groups.($def.key)) { $state = 'shared' }
        elseif (@($ours | Where-Object { $_.name -eq $name }).Count) { $state = 'ours' }
        elseif ($def.ask -eq 'group' -and $resources.Count) { $state = 'ours' }
        $group = ''
        if ($saved.groups) { $group = [string]$saved.groups.($def.key) }
        Mark $def.key $name $state $group
    }
    # The apps' identities, for their roles on a shared vault elsewhere.
    $identities = @(foreach ($def in @($defs | Where-Object { $_.armType -eq 'Microsoft.Web/sites' -and $saved.names.($_.key) })) { Try-Az @('webapp', 'show', '-g', $rgName, '-n', $saved.names.($def.key)) })
    $deployDef = $defs | Where-Object { $_.ask -eq 'name' -and $_.type -eq 'deploy' } | Select-Object -First 1
    $deployApp = [string]$saved.names.($deployDef.key)
    $entra = @(Invoke-Az @('ad', 'app', 'list', '--display-name', $deployApp)) | Where-Object { $_ } | Select-Object -First 1
    if ($entra) { Mark $deployDef.key $deployApp 'ours' '' }
    $haveGh = $ghExe -and (Test-Gh @('auth', 'status'))
    $repo = [string]$saved.repo
    $haveEnv = $haveGh -and $repo -and (Test-Gh @('api', "repos/$repo/environments/$ghEnv"))
    $vaultOurs = @($ours | Where-Object { $_.type -eq 'Microsoft.KeyVault/vaults' }) | Select-Object -First 1
    $wholeGroup = $resources.Count -gt 0 -and $others.Count -eq 0

    Head "What would be removed ($envAbbr, $ghEnv)"
    if ($envAbbr -eq 'prod') { Say '    THIS IS PRODUCTION: its live apps stop.' 'Red' }
    if (-not $resources.Count) { Note "Azure: resource group $rgName is empty or gone" }
    elseif ($wholeGroup) { Note "Azure: resource group $rgName with everything in it:" }
    else { Note "Azure, in resource group ${rgName}:" }
    foreach ($r in $ours) { Note ("  delete  {0,-52} {1}" -f $r.name, $r.type) }
    foreach ($r in $others) { Note ("  keep    {0,-52} {1} (not made by the setup)" -f $r.name, $r.type) }
    foreach ($def in @($defs | Where-Object { $_.groupParam -and $saved.groups -and $saved.groups.($_.key) })) {
        Note ("  keep    {0,-52} shared from {1}" -f $saved.names.($def.key), $saved.groups.($def.key))
    }
    if ($entra) { Note "Entra: app registration $deployApp (GitHub Actions' sign-in to Azure) and its service principal" }
    if ($haveEnv) { Note "GitHub: environment $ghEnv of $repo (its variables, deployment token and branch rule)" }
    elseif (-not $haveGh) { Note "GitHub: not checked (no GitHub CLI); delete the environment $ghEnv by hand: https://github.com/$repo/settings/environments" }
    if ($vaultOurs) { Note "Key Vault $($vaultOurs.name): deleted vaults stay recoverable for 30 days and keep their name; you are asked whether to purge it" }
    Note 'Not touched: the DNS records (listed at the end), the code, the workflows.'

    if (-not $ours.Count -and -not $entra -and -not $haveEnv) {
        Ok 'nothing of this environment is left'
    } else {
        Say ''
        $question = "To remove all of this, type the resource group's name ($rgName), anything else cancels"
        $typed = Read-Answer "  ${question}: " ([ordered]@{ kind = 'text'; question = $question; default = ''; danger = $true })
        if ($typed -cne $rgName) {
            Note 'cancelled, nothing was changed'
            if ($script:ui) { Send ([ordered]@{ t = 'summary'; env = $envAbbr; ghEnv = $ghEnv; open = @(); code = 1; cancelled = $true }) }
            return 1
        }

        Head 'Removing'
        if ($haveEnv) {
            Invoke-Gh @('api', '-X', 'DELETE', "repos/$repo/environments/$ghEnv") | Out-Null
            Ok "GitHub environment $ghEnv deleted"
        }
        if ($entra) {
            Invoke-Az @('ad', 'app', 'delete', '--id', $entra.appId) | Out-Null # its service principal and federated credentials go with it
            Ok "app registration $deployApp deleted"
            Mark $deployDef.key $deployApp 'gone' ''
        }
        # An app's role on a shared vault elsewhere would stay as an "unknown" principal: removed first.
        foreach ($vdef in @($defs | Where-Object { $_.armType -eq 'Microsoft.KeyVault/vaults' -and $saved.groups -and $saved.groups.($_.key) })) {
            $vaultId = "/subscriptions/$($saved.subscriptionId)/resourceGroups/$($saved.groups.($vdef.key))/providers/$($vdef.armType)/$($saved.names.($vdef.key))"
            foreach ($app in $identities) {
                if (-not ($app -and $app.identity -and $app.identity.principalId)) { continue }
                Try-Az @('role', 'assignment', 'delete', '--assignee', $app.identity.principalId, '--scope', $vaultId) | Out-Null
                Ok "the access of $($app.name) to the shared vault $($saved.names.($vdef.key)) removed"
            }
        }
        if ($wholeGroup) {
            Note "deleting resource group $rgName (a few minutes)..."
            Invoke-Az @('group', 'delete', '-n', $rgName, '--yes') | Out-Null
            Ok "resource group $rgName deleted"
            foreach ($def in $defs) { if ($saved.names.($def.key) -and -not ($saved.groups -and $saved.groups.($def.key)) -and $def.ask -ne 'name') { Mark $def.key $saved.names.($def.key) 'gone' '' } }
        } elseif ($ours.Count) {
            # In the map's removeOrder: apps before their plan, the plan and the workspace last.
            $order = @($map.removeOrder | ForEach-Object { $_.ToLower() })
            $sorted = @($ours | Sort-Object { $i = [array]::IndexOf($order, $_.type.ToLower()); if ($i -lt 0) { 99 } else { $i } })
            foreach ($r in $sorted) {
                Invoke-Az @('resource', 'delete', '--ids', $r.id) | Out-Null
                Ok "$($r.name) deleted"
                $def = $defs | Where-Object { $saved.names.($_.key) -eq $r.name } | Select-Object -First 1
                if ($def) { Mark $def.key $r.name 'gone' '' }
            }
        }
        if ($vaultOurs) {
            $deleted = Try-Az @('keyvault', 'show-deleted', '--name', $vaultOurs.name)
            if ($deleted -and (Confirm-Step "Purge Key Vault $($vaultOurs.name) now (frees its name; its secrets can't be recovered then)?" -DefaultNo -Danger)) {
                Invoke-Az @('keyvault', 'purge', '--name', $vaultOurs.name) | Out-Null
                Ok "Key Vault $($vaultOurs.name) purged"
            } elseif ($deleted) { Note "Key Vault $($vaultOurs.name) stays recoverable until $(([string]$deleted.properties.scheduledPurgeDate).Split('T')[0]) (az keyvault recover --name $($vaultOurs.name))" }
        }
    }

    if (Confirm-Step "Delete infra/environments/$envAbbr.json as well (the workflows then stop deploying for $ghEnv)?" -DefaultNo) {
        Remove-Item $envFile
        Ok "infra/environments/$envAbbr.json deleted (commit it)"
    } else { Note "infra/environments/$envAbbr.json kept: Start recreates the environment with the same answers" }

    $records = @()
    foreach ($dm in @($map.domains)) {
        $domain = [string]$saved.($dm.answer)
        if (-not $domain -or $domain -eq '-') { continue }
        $records += New-DnsRecord 'CNAME' $domain "(the removed $($dm.what))"
        if ($dm.dns -eq 'appService') { $records += New-DnsRecord 'TXT' "asuid.$domain" '(its verification id)' }
    }
    if ($records.Count) {
        $zones = (@($records | ForEach-Object { Get-Zone $_.Name }) | Select-Object -Unique) -join ', '
        $lines = @($records | ForEach-Object { "delete {0,-5}  {1}" -f $_.Type, (Get-RelativeName $_.Name) })
        $lines += '(a CNAME left pointing at a deleted Azure address can be taken over by someone else''s app)'
        Head 'Next steps (by hand)'
        if ($script:ui) { Send ([ordered]@{ t = 'steps'; items = @([ordered]@{ title = 'Remove the DNS records of the custom domains'; where = "the DNS host of $zones"; what = $lines }) }) }
        else {
            Write-Host ''
            Write-Host '  1. Remove the DNS records of the custom domains' -ForegroundColor Cyan
            Write-Host "       Where: the DNS host of $zones"
            Write-Host '       What:'
            foreach ($line in $lines) { Write-Host "         $line" }
        }
    }
    if ($script:ui) {
        Send ([ordered]@{ t = 'summary'; env = $envAbbr; ghEnv = $ghEnv; open = @(); code = 0; removed = $true })
        return 0
    }
    Write-Host ''
    Write-Host "$envAbbr ($ghEnv): removed." -ForegroundColor Green
    return 0
}

# What to do: a switch, else the help and then the menu.
function Select-Mode {
    if ($DryRun) { return 'dryrun' }
    if ($Check) { return 'check' }
    if ($Start) { return 'start' }
    if ($Remove) { return 'remove' }
    if ($AddResource) { return 'addresource' }
    if ($RemoveResource) { return 'removeresource' }
    if ($Init -or -not $map) { return 'init' }
    if ($script:ui) { throw '-Ui needs -DryRun, -Check, -Start, -Remove, -AddResource or -RemoveResource.' }
    Show-Usage
    Write-Host 'What to do?' -ForegroundColor Cyan
    Write-Host '  1. Dry run - asks every question, shows what would be created or changed; changes nothing'
    Write-Host '  2. Check   - checks a set-up environment with its saved answers, no questions; changes nothing'
    Write-Host '  3. Start   - asks every question, then creates and updates what is missing (each change asked first)'
    Write-Host '  4. Remove all - deletes what the setup created for an environment (shown first, confirmed by typing its name)'
    Write-Host '  5. Add a resource to the map (from infra/catalog), then generate main.bicep'
    Write-Host '  6. Remove a resource from the map, then generate main.bicep'
    Write-Host '  q. Quit'
    while ($true) {
        $choice = (Read-Answer '  Choice [1]: ' ([ordered]@{ kind = 'menu'; question = 'What to do?'; default = '1' })).ToLower()
        if (@('', '1', 'd', 'dry run') -contains $choice) { return 'dryrun' }
        if (@('2', 'c', 'check') -contains $choice) { return 'check' }
        if (@('3', 's', 'start') -contains $choice) { return 'start' }
        if (@('4', 'r', 'remove') -contains $choice) { return 'remove' }
        if (@('5', 'a', 'add') -contains $choice) { return 'addresource' }
        if (@('6', 'x') -contains $choice) { return 'removeresource' }
        if (@('q', 'quit') -contains $choice) { return 'quit' }
        Note 'X 1 to 6 or q'
    }
}

$code = 1
try {
    if (-not $script:ui) { Show-Author }
    $script:mode = Select-Mode
    if (-not $map -and @('init', 'quit') -notcontains $script:mode) { throw 'There is no infra/infra.map.json yet: start the project with .\infra\azure-setup.ps1 -Init (or .\infra\lazyazure.ps1).' }
    if ($script:mode -eq 'quit') { $code = 0 }
    elseif ($script:mode -eq 'remove') { $code = Invoke-Remove }
    else {
        # The map's modes write files only at their end, so '<' works in them too until then.
        $mapMode = @('init', 'addresource', 'removeresource') -contains $script:mode
        $script:readOnly = $script:mode -ne 'start' -and -not $mapMode
        $script:auto = $script:mode -eq 'check'
        $script:typed.Clear() # the menu's answer isn't one of the questions
        while ($true) {
            $script:results.Clear()
            $script:dnsTodo.Clear()
            $script:canGoBack = $true
            $script:auto = $script:mode -eq 'check'
            $script:lastAuto = $null
            if ($mapMode) { Reset-MapState }
            try {
                switch ($script:mode) {
                    'init' { $code = Invoke-Init }
                    'addresource' { $code = Invoke-AddResource }
                    'removeresource' { $code = Invoke-RemoveResource }
                    default { $code = Invoke-Setup }
                }
                break
            } catch {
                if ($_.Exception.Message -ne $backSignal) { throw }
                # Everything typed except the last answer is answered again; the question before it comes up.
                $earlier = @($script:typed)
                $script:typed = New-Object System.Collections.ArrayList
                $script:replay = New-Object System.Collections.ArrayList
                for ($i = 0; $i -lt $earlier.Count - 1; $i++) { [void]$script:replay.Add($earlier[$i]) }
                # The question asked again shows what was answered before (to change it, or keep it).
                $script:previous = $null
                if ($earlier.Count) { $script:previous = $earlier[$earlier.Count - 1] }
                $script:replaying = $script:replay.Count -gt 0
                if ($script:ui) { Send ([ordered]@{ t = 'back' }) } else { Write-Host '    (back)' -ForegroundColor DarkGray }
            }
        }
    }
}
catch {
    if ($script:ui) { Send ([ordered]@{ t = 'error'; text = $_.Exception.Message }) }
    else { Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Red }
}
finally {
    if ($script:sqlRules.Count) { try { Close-SqlFirewall } catch { } }
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
exit $code

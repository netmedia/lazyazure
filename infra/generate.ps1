#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyAzure  -  generate.ps1                                             ║
#  ║   Makes main.bicep from the map and the catalog                          ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyAzure  -  https://github.com/netmedia/lazyazure          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
LazyAzure by Netmedia: makes infra/main.bicep from infra/infra.map.json and infra/catalog/.

.AUTHOR
Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
main.bicep is generated: one section per resource of the map, from its kind's fragment in
infra/catalog/<kind>.bicep (several resources of one kind each get their own, named by their key), the
apps' settings from their "appSettings" ({braces} become Bicep expressions), the role assignments from the
"role" connections, the Key Vault's readers and secrets. Change the map or the catalog, never main.bicep;
then run this, and a dry run shows what would change in Azure.

Values in {braces}: {<key>.name} (its name parameter), {<key>.host}, {<key>.id}, {<key>.connectionString}
(Application Insights), {<key>.tableEndpoint} / queueEndpoint / blobEndpoint (storage), {<answer>} (a
custom domain's parameter, e.g. {webDomain}), {secret.<name>} (a secret the setup keeps), {kvdns}
(.vault.azure.net), {env}; 'a|b' takes b when a is empty (an unset domain, a resource that isn't used).

.PARAMETER Check
Only compares: exits with 1 when main.bicep isn't what the map makes (infra/azure-setup.ps1 checks this).

.PARAMETER Quiet
No output (for -Check from the setup).

.PARAMETER Help
Shows the usage guide and exits.

.EXAMPLE
.\infra\generate.ps1

.NOTES
LazyAzure is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
https://github.com/netmedia/lazyazure.

.LINK
infra/LAZYAZURE.md
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Quiet,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$infra = $PSScriptRoot

# --- Netmedia: who made it, how to use it ---------------------------------------------------------------

function Show-Author {
    $width = 64
    $hLine = [string]::new([char]0x2500, $width)
    $v = [char]0x2502
    $esc = [char]27
    $version = ''
    if (Test-Path (Join-Path $infra 'kit.json')) { $version = (Get-Content (Join-Path $infra 'kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version }
    function Row([string]$display, [string]$measure = $display, [string]$color = 'White') {
        $pad = [Math]::Max(0, $width - $measure.Length)
        $left = [Math]::Floor($pad / 2)
        Write-Host "  $v" -NoNewline -ForegroundColor Cyan
        Write-Host "$(' ' * $left)$display$(' ' * ($pad - $left))" -NoNewline -ForegroundColor $color
        Write-Host $v -ForegroundColor Cyan
    }
    $title = 'LazyAzure  -  generate.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'Makes main.bicep from the map and the catalog' -color 'White'
    Row ''
    Row "by Netmedia$(if ($version) { "  |  LazyAzure $version" })" -color 'DarkGray'
    Row 'https://netmedia.agency  |  netmedia@netmedia.hr' -color 'DarkGray'
    Row ''
    Write-Host "  $([char]0x2570)$hLine$([char]0x256F)" -ForegroundColor Cyan
    Write-Host ''
}
function Show-Usage {
    $b = { param($t) Write-Host "  $t" -ForegroundColor White }
    $d = { param($t) Write-Host "  $t" -ForegroundColor DarkGray }
    $g = { param($t) Write-Host "  $t" -ForegroundColor Green }
    $y = { param($t) Write-Host "  $t" -ForegroundColor Yellow }
    & $b 'USAGE'
    & $g '  .\infra\generate.ps1  [-Check]  [-Quiet]'
    & $d '  main.bicep is generated: never edit it. Change infra\infra.map.json (or add and'
    & $d '  remove resources with .\infra\azure-setup.ps1 -AddResource / -RemoveResource,'
    & $d '  which run this), then a dry run shows what changes in Azure.'
    Write-Host ''
    & $b 'OPTIONS'
    & $y '  -Check'
    & $d '    Only compares: exit 1 when main.bicep isn''t what the map makes.'
    & $y '  -Quiet'
    & $d '    No output (the setup checks with -Check -Quiet before every what-if).'
    & $y '  -Help  (-h)'
    & $d '    Shows this guide and exits.'
    Write-Host ''
    & $d '  More: infra\LAZYAZURE.md ("The catalog")'
    Write-Host ''
}
if ($Help) { Show-Author; Show-Usage; exit 0 }
if (-not $Quiet) { Show-Author }

$map = Get-Content (Join-Path $infra 'infra.map.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$roles = Get-Content (Join-Path $infra 'catalog\roles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$naming = Get-Content (Join-Path $infra 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$actions = Get-Content (Join-Path $infra 'catalog\workflows\actions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$defs = @($map.resources)
$noBicep = @('resourceGroup', 'entraDeployApp') # made by the setup itself
$target = Join-Path $infra ([string]$map.project.template)

function Get-Def([string]$Key) { return $defs | Where-Object { $_.key -eq $Key } | Select-Object -First 1 }
function Get-Links([string]$From, [string]$Kind) { return @($map.connections | Where-Object { $_.from -eq $From -and $_.kind -eq $Kind }) }
function Get-LinksTo([string]$To, [string]$Kind) { return @($map.connections | Where-Object { @($_.to.Split('|')) -contains $To -and $_.kind -eq $Kind }) }
function Test-Optional($Def) { return [bool]($Def.optional -or $Def.when) }
function Fail([string]$Text) { throw "infra.map.json: $Text" }

# --- {braces} to Bicep -------------------------------------------------------------------------------

function Get-TokenBicep([string]$Token) {
    if ($Token -eq 'kvdns') { return 'environment().suffixes.keyvaultDns' }
    if ($Token -eq 'env') { return 'environmentName' }
    if ($Token.StartsWith('secret.')) {
        $name = $Token.Substring(7)
        foreach ($d in $defs) { foreach ($s in @($d.secrets)) { if ($s -and $s.name -eq $name -and $s.param) { return [string]$s.param } } }
        Fail "{$Token}: no secret $name that the setup keeps (secrets, by: setup)"
    }
    $domain = @($map.domains) | Where-Object { $_.answer -eq $Token } | Select-Object -First 1
    if ($domain) {
        if (-not $domain.param) { Fail "{$Token}: the domain has no main.bicep parameter (param)" }
        return [string]$domain.param
    }
    $parts = $Token.Split('.')
    $d = Get-Def $parts[0]
    if (-not $d -or $parts.Count -ne 2) { Fail "{$Token}: no such resource or value" }
    $key = $d.key
    switch ($parts[1]) {
        'name' { return [string]$d.param }
        'id' { return "$key.id" }
        'host' {
            switch ([string]$d.kind) {
                'staticWebApp' { return "$key.properties.defaultHostname" }
                # Known from the name (the server may be shared from another group).
                'sqlServer' { return "'`${$($d.param)}`${environment().suffixes.sqlServerHostname}'" }
                'serviceBus' { return "'`${$($d.param)}.servicebus.windows.net'" }
            }
            return "$key.properties.defaultHostName"
        }
        'connectionString' { return "${key}Connection" }
        'tableEndpoint' { return "$key.properties.primaryEndpoints.table" }
        'queueEndpoint' { return "$key.properties.primaryEndpoints.queue" }
        'blobEndpoint' { return "$key.properties.primaryEndpoints.blob" }
    }
    Fail "{$Token}: $($parts[1]) isn't a value of a resource"
}
# When a value can be empty (an unset domain, a resource only some answers use): the test for it.
function Get-TokenGuard([string]$Token) {
    $domain = @($map.domains) | Where-Object { $_.answer -eq $Token } | Select-Object -First 1
    if ($domain) { return "empty($($domain.param))" }
    $d = Get-Def ($Token.Split('.')[0])
    if ($d -and (Test-Optional $d)) { return "empty($($d.param))" }
    return $null
}
function Get-AltBicep([string]$Inner) {
    $alts = $Inner.Split('|')
    $expr = Get-TokenBicep $alts[-1]
    for ($i = $alts.Count - 2; $i -ge 0; $i--) {
        $guard = Get-TokenGuard $alts[$i]
        $token = Get-TokenBicep $alts[$i]
        if ($guard) { $expr = "$guard ? $expr : $token" } else { $expr = $token }
    }
    return $expr
}
function Get-ValueBicep([string]$Value) {
    $matches_ = @([regex]::Matches($Value, '\{([^{}]+)\}'))
    if ($matches_.Count -eq 1 -and $matches_[0].Value -eq $Value) { return Get-AltBicep $matches_[0].Groups[1].Value }
    $out = "'"
    $at = 0
    foreach ($m in $matches_) {
        $expr = Get-AltBicep $m.Groups[1].Value
        # A value that is itself an interpolated string ('${a}.b') goes in as it is.
        if ($expr -match "^'([^']*)'$") { $piece = $Matches[1] } else { $piece = '${' + $expr + '}' }
        $out += (Get-Literal $Value.Substring($at, $m.Index - $at)) + $piece
        $at = $m.Index + $m.Length
    }
    return $out + (Get-Literal $Value.Substring($at)) + "'"
}
function Get-Literal([string]$Text) { return $Text.Replace('\', '\\').Replace("'", "\'").Replace('${', '\${') }
function Get-Quoted([string]$Text) { return "'" + (Get-Literal $Text) + "'" }
function Get-PropName([string]$Name) { if ($Name -match '^[A-Za-z_][A-Za-z0-9_]*$') { return $Name } return (Get-Quoted $Name) }

function Get-SettingsArray($Def, [string]$Indent) {
    $lines = @('[')
    foreach ($s in @($Def.appSettings)) {
        if ($s.about) { $lines += "$Indent  // $($s.about)" }
        $lines += "$Indent  { name: $(Get-Quoted $s.name), value: $(Get-ValueBicep $s.value) }"
    }
    return ($lines + "$Indent]") -join "`n"
}
function Get-SettingsObject($Def, [string]$Indent) {
    $lines = @('{')
    foreach ($s in @($Def.appSettings)) {
        if ($s.about) { $lines += "$Indent  // $($s.about)" }
        $lines += "$Indent  $(Get-PropName $s.name): $(Get-ValueBicep $s.value)"
    }
    return ($lines + "$Indent}") -join "`n"
}

# --- fragments -------------------------------------------------------------------------------------------

function Get-Fragment([string]$Kind, [hashtable]$Values, [hashtable]$Flags, [string]$File) {
    $file = $File
    if (-not $file) { $file = Join-Path $infra "catalog\$Kind.bicep" }
    if (-not (Test-Path $file)) { Fail "no $($file.Substring($infra.Length + 1)) for kind $Kind" }
    $text = (Get-Content $file -Raw -Encoding UTF8).Replace("`r`n", "`n")
    # A placeholder alone on its line with nothing to fill: the line goes (no empty lines in YAML steps).
    foreach ($k in $Values.Keys) { if (-not [string]$Values[$k]) { $text = [regex]::Replace($text, "(?m)^[ \t]*\{\{$k\}\}\n", '') } }
    $text = [regex]::Replace($text, '(?ms)^//#if (\w+)\n(.*?)^//#end\n', [Text.RegularExpressions.MatchEvaluator] {
            param($m)
            if ($Flags[$m.Groups[1].Value]) { return $m.Groups[2].Value }
            return ''
        })
    foreach ($k in $Values.Keys) { $text = $text.Replace("{{$k}}", [string]$Values[$k]) }
    # Actions by their short names (catalog/workflows/actions.json).
    $text = [regex]::Replace($text, '\{\{action:([\w-]+)\}\}', [Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $a = $actions.($m.Groups[1].Value)
            if (-not $a) { Fail "catalog/workflows/actions.json has no action $($m.Groups[1].Value)" }
            return [string]$a
        })
    $left = [regex]::Match($text, '\{\{(\w+)\}\}')
    if ($left.Success) { Fail "catalog/$Kind.bicep: nothing fills {{$($left.Groups[1].Value)}}" }
    return $text.TrimEnd()
}
function Get-SizeOptions($Def) { return '[' + ((@($Def.size.options) | ForEach-Object { Get-Quoted $_ }) -join ', ') + ']' }

# The values of one resource's fragment.
function Get-Section($Def) {
    $key = [string]$Def.key
    $v = @{ key = $key; name = [string]$Def.param; group = [string]$Def.groupParam; title = [string]$Def.title }
    $f = @{}
    if ($Def.size) { $v.size = [string]$Def.size.param; $v.sizeOptions = Get-SizeOptions $Def; $v.sizeDefault = [string]$Def.size.default }
    switch ([string]$Def.kind) {
        'appService' {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            if (-not $host_) { Fail "$key needs a host connection (the App Service plan it runs on)" }
            $v.hostId = "$($host_.to)Id"
            $v.runtime = [string]$Def.runtime
            $v.healthCheckPath = [string]$Def.healthCheckPath
            $f.health = [bool]$Def.healthCheckPath
            $v.settingsArray = Get-SettingsArray $Def '      '
        }
        'staticWebApp' {
            $f.settings = [bool]@($Def.appSettings).Count
            if ($f.settings) { $v.settingsObject = Get-SettingsObject $Def '  ' }
        }
        'functionApp' {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            if (-not $host_) { Fail "$key needs a host connection (the plan it runs on)" }
            $v.hostId = "$($host_.to)Id"
            $f.flex = (Get-Def $host_.to).kind -eq 'flexPlan'
            $f.plan = -not $f.flex
            $v.runtime = [string]$Def.runtime
            $parts = ([string]$Def.runtime).Split('|')
            $v.runtimeName = $parts[0].ToLower()
            $v.runtimeVersion = $parts[-1]
            if ($f.flex) {
                $store = Get-Def ([string]$Def.stateStorage)
                if (-not $store) { Fail "$key (Flex Consumption) needs stateStorage: the storage account for its packages and state" }
                $v.storage = $store.key
                $v.storageTitle = $store.title
                $v.container = ($key.ToLower() + '-packages')
            }
            $v.settingsArray = Get-SettingsArray $Def '      '
        }
        'sqlServer' {
            $v.adminLogin = [string]$Def.admin.loginParam
            $v.adminSid = [string]$Def.admin.sidParam
            $v.adminType = [string]$Def.admin.typeParam
        }
        'sqlDatabase' {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            $server = $null
            if ($host_) { $server = Get-Def $host_.to }
            if (-not $server -or $server.kind -ne 'sqlServer') { Fail "$key needs a host connection to its SQL server" }
            $v.server = $server.key
            $v.serverName = $server.param
            $v.serverTitle = $server.title
            $v.deployName = "'sql-database-`${$($Def.param)}'"
        }
        'serviceBus' {
            $lines = @()
            $i = 0
            foreach ($q in @($Def.queues | Where-Object { $_ })) {
                $i++
                $lines += ''
                $lines += "resource $($key)Queue$i 'Microsoft.ServiceBus/namespaces/queues@2021-11-01' = {"
                $lines += "  parent: $key"
                $lines += "  name: $(Get-Quoted $q)"
                $lines += "  properties: { maxDeliveryCount: 10, lockDuration: 'PT1M', deadLetteringOnMessageExpiration: true }"
                $lines += '}'
            }
            $v.queues = $lines -join "`n"
        }
        'storageQueue' {
            $host_ = @(Get-Links $key 'host') | Select-Object -First 1
            $parent = $null
            if ($host_) { $parent = Get-Def $host_.to }
            if (-not $parent -or $parent.kind -ne 'storage') { Fail "$key needs a host connection to its storage account" }
            $v.parent = $parent.key
            $v.parentTitle = $parent.title
        }
        'logAnalytics' {
            $users = @(Get-LinksTo $key 'logs' | ForEach-Object { "$($_.from)New" })
            $v.needed = 'false'
            if ($users.Count) { $v.needed = $users -join ' || ' }
        }
        'appInsights' {
            $ws = @(Get-Links $key 'logs') | Select-Object -First 1
            if (-not $ws) { Fail "$key needs a logs connection (its Log Analytics workspace)" }
            $v.workspaceId = "$($ws.to)Id"
            $n = $v.name
            $g = $v.group
            if (Test-Optional $Def) {
                $v.nameDefault = " = ''"
                $v.optionalNote = ' Empty: none.'
                $v.newExpr = "!empty($n) && empty($g)"
                $v.existingExpr = "!empty($n) && !empty($g)"
                $v.nameExpr = "!empty($n) ? $n : 'none'"
            } else {
                $v.nameDefault = ''
                $v.optionalNote = ''
                $v.newExpr = "empty($g)"
                $v.existingExpr = "!empty($g)"
                $v.nameExpr = $n
            }
        }
        'keyVault' {
            $readers = @(Get-LinksTo $key 'role' | Where-Object { @($_.roles) -contains 'Key Vault Secrets User' } | ForEach-Object { $_.from })
            foreach ($c in @(Get-LinksTo $key 'role')) { foreach ($r in @($c.roles)) { if ($r -ne 'Key Vault Secrets User') { Fail "$($c.from) -> ${key}: role $r on a Key Vault isn't supported yet (only Key Vault Secrets User)" } } }
            $first = $v.name
            if ($readers.Count) { $first = (Get-Def $readers[0]).param }
            $v.accessName = "'vault-access-`${$first}'"
            if ($readers.Count) { $v.readers = "[`n" + ((@($readers | ForEach-Object { "      { id: $_.id, principalId: $_.identity.principalId }" })) -join "`n") + "`n    ]" } else { $v.readers = '[]' }
            $kept = @(@($Def.secrets) | Where-Object { $_ -and $_.by -eq 'setup' })
            if ($kept.Count) {
                $v.secretValues = "{`n" + ((@($kept | ForEach-Object { "      $(Get-Quoted $_.name): $($_.param)" })) -join "`n") + "`n    }"
                $writes = @($kept | ForEach-Object { "$($_.writeParam) ? [$(Get-Quoted $_.name)] : []" })
                if ($writes.Count -eq 1) { $v.writeSecrets = $writes[0] } else { $v.writeSecrets = "concat($($writes -join ', '))" }
            } else { $v.secretValues = '{}'; $v.writeSecrets = '[]' }
        }
    }
    return Get-Fragment ([string]$Def.kind) $v $f
}

# --- main.bicep --------------------------------------------------------------------------------------------

function Get-Bicep {
    foreach ($d in $defs) { if (-not $d.kind) { Fail "$($d.key) has no kind" } }
    $out = New-Object Collections.Generic.List[string]
    $out.Add('// GENERATED by infra/generate.ps1 from infra/infra.map.json and infra/catalog/: don''t edit it here.')
    $out.Add('// Change the map (infra/README.md, "The map") or the catalog, then run .\infra\generate.ps1.')
    $out.Add('//')
    $out.Add("// $($map.project.name): $($map.project.description).")
    $out.Add('// Every name comes from infra/azure-setup.ps1 (infra/naming.json rules, infra/environments/<env>.json); a')
    $out.Add('// shared resource with an empty <x>Group is created and managed here (tagged managed-by), otherwise it is an')
    $out.Add('// existing one of that group, used as it is.')
    $out.Add('')
    $out.Add("@description('Region of every new resource except the Static Web Apps.')")
    $out.Add('param location string = resourceGroup().location')
    if (@($defs | Where-Object { $_.kind -eq 'staticWebApp' }).Count) {
        $out.Add('')
        $out.Add("@description('Region of the Static Web Apps (offered in a few regions only).')")
        $out.Add("@allowed([$((@($map.regions.staticWebApp) | ForEach-Object { Get-Quoted $_ }) -join ', ')])")
        $out.Add("param staticLocation string = $(Get-Quoted $map.regions.default)")
    }
    $out.Add('')
    $out.Add("@description('Environment, full name (production, test, staging, development, acceptance): a tag.')")
    $out.Add('param environmentName string')
    $out.Add('')
    $out.Add("@description('Client-project and sub application prefix: a tag.')")
    $out.Add('param project string')
    foreach ($dm in @($map.domains | Where-Object { $_.param })) {
        $out.Add('')
        $out.Add("@description('The custom domain of the $($dm.what); empty = none yet.')")
        $out.Add("param $($dm.param) string = ''")
    }
    if (@($defs | Where-Object { $_.kind -eq 'keyVault' }).Count) {
        $out.Add('')
        $out.Add("@description('Object id of the person running the setup: Key Vault Secrets Officer (for the secrets put in by hand); empty = none.')")
        $out.Add("param ownerObjectId string = ''")
    }
    foreach ($d in $defs) {
        foreach ($s in @($d.secrets | Where-Object { $_ -and $_.by -eq 'setup' })) {
            $out.Add('')
            $out.Add("@description($(Get-Quoted "$($s.about); kept in the vault."))")
            $out.Add('@secure()')
            $out.Add("param $($s.param) string")
            $out.Add('')
            $out.Add("@description('Write $($s.param) to the vault (infra/azure-setup.ps1: only when it is missing there or differs).')")
            $out.Add("param $($s.writeParam) bool = true")
        }
    }
    $out.Add('')
    $out.Add("var tags = { project: project, environment: environmentName, 'managed-by': $(Get-Quoted $map.project.managedByTag) }")
    $out.Add('var here = resourceGroup().name')

    foreach ($d in $defs) {
        if ($noBicep -contains $d.kind) { continue }
        $out.Add('')
        $out.Add("// --- $($d.title) ($($d.key), $($d.kind)) $('-' * [Math]::Max(3, 90 - $d.title.Length - $d.key.Length - $d.kind.Length))")
        $out.Add('')
        $out.Add((Get-Section $d))
    }

    # Roles of the apps' managed identities (Key Vault roles: in its module above).
    $n = 0
    foreach ($c in @($map.connections | Where-Object { $_.kind -eq 'role' })) {
        $to = Get-Def $c.to
        $from = Get-Def $c.from
        if (-not $to -or -not $from) { Fail "role connection $($c.from) -> $($c.to): no such resource" }
        if ($to.kind -eq 'keyVault') { continue }
        if ($to.groupParam) { Fail "role connection $($c.from) -> $($c.to): roles on a resource that may be shared from another group aren't supported yet" }
        foreach ($role in @($c.roles)) {
            $id = $roles.$role
            if (-not $id) { Fail "role '$role': not in catalog/roles.json" }
            $n++
            if ($n -eq 1) { $out.Add(''); $out.Add('// --- Roles of the apps'' managed identities ' + ('-' * 60)) }
            $sym = "$($from.key)Role$n"
            $out.Add('')
            $out.Add("// $($from.title) -> $($to.title): $role$(if ($c.what) { " ($($c.what))" })")
            $out.Add("resource $sym 'Microsoft.Authorization/roleAssignments@2022-04-01' = {")
            $out.Add("  scope: $($to.key)")
            $out.Add("  name: guid($($to.key).id, $($from.key).id, '$id')")
            $out.Add('  properties: {')
            $out.Add("    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '$id')")
            $out.Add("    principalId: $($from.key).identity.principalId")
            $out.Add("    principalType: 'ServicePrincipal'")
            $out.Add('  }')
            $out.Add('}')
        }
    }

    $out.Add('')
    foreach ($d in $defs) {
        if ($d.kind -eq 'appService' -or $d.kind -eq 'functionApp') {
            $out.Add("output $($d.key)HostName string = $($d.key).properties.defaultHostName")
            $out.Add("output $($d.key)VerificationId string = $($d.key).properties.customDomainVerificationId")
        } elseif ($d.kind -eq 'staticWebApp') { $out.Add("output $($d.key)HostName string = $($d.key).properties.defaultHostname") }
    }
    return (($out -join "`n") + "`n")
}

# --- the deploy workflows (.github/workflows) ---------------------------------------------------------------

# Each app with a "deploy" in the map gets its GitHub Actions workflow, from catalog/workflows/<kind>.yml:
# what it builds from which folder (its source and paths: the push trigger), how, and where it publishes
# (its app in the environment the branch belongs to: infra/route.ps1). The push trigger's branches are the
# environments' deploy branches (infra/environments/*.json), or every branch when the app tests on all.
$repoRoot = Split-Path $infra -Parent
$workflowDir = Join-Path $repoRoot '.github\workflows'
$generatedMark = '# GENERATED by infra/generate.ps1'

function Get-EnvBranches {
    return @(Get-ChildItem (Join-Path $infra 'environments') -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object { [string](Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).branch } |
            Where-Object { $_ -and $_ -ne '-' } | Sort-Object -Unique)
}
function Get-YamlQuoted([string]$Text) { return "'" + $Text.Replace("'", "''") + "'" }
# A step of the map: { name, id, workingDirectory, run, comment }; $If on every step of a job that skips
# when the environment isn't set up.
# An action by its short name in catalog/workflows/actions.json (checkout -> actions/checkout@v7), or as given.
function Get-Action([string]$Name) {
    if ($actions.$Name) { return [string]$actions.$Name }
    return $Name
}
# A value of "with:" or an input: numbers and booleans as they are; text plain when YAML reads it as text,
# else quoted (a version like '8.7' stays text).
function Get-YamlValue($Value) {
    if ($Value -is [bool]) { if ($Value) { return 'true' } return 'false' }
    if ($Value -is [ValueType]) { return [string]$Value }
    $t = [string]$Value
    if ($t -match '^[0-9]' -or $t -match ': | #' -or $t -match '^[\[\]{}&*!|>''"%@`#,?:-]' -or @('true', 'false', 'null', 'yes', 'no', '~', '') -contains $t.ToLower()) { return Get-YamlQuoted $t }
    return $t
}
# A step of the map: { comment, name, if, id, uses, with, workingDirectory, run }; $If on every step of a
# job that skips when the environment isn't set up.
function Get-StepYaml($Step, [string]$If) {
    $lines = @()
    foreach ($c in @($Step.comment | Where-Object { $_ })) { $lines += "      # $c" }
    $fields = @()
    if ($Step.name) { $fields += "name: $($Step.name)" }
    $condition = $If
    if ($Step.if) { $condition = [string]$Step.if }
    if ($condition) { $fields += "if: $condition" }
    if ($Step.id) { $fields += "id: $($Step.id)" }
    if ($Step.uses) { $fields += "uses: $(Get-Action ([string]$Step.uses))" }
    if ($Step.with) {
        $fields += 'with:'
        foreach ($p in $Step.with.PSObject.Properties) { $fields += "  $($p.Name): $(Get-YamlValue $p.Value)" }
    }
    if ($Step.workingDirectory) { $fields += "working-directory: $($Step.workingDirectory)" }
    if ($Step.shell) { $fields += "shell: $($Step.shell)" }
    if ($Step.run) {
        $run = ([string]$Step.run).Replace("`r", '')
        # One plain line when YAML reads it as it is, else a block.
        if ($run -notmatch "`n" -and $run -notmatch ': | #' -and $run -notmatch '^[\[\]{}&*!|>''"%@`#,?:-]') { $fields += "run: $run" }
        else {
            $fields += 'run: |'
            foreach ($l in $run.Split("`n")) { $fields += "  $l" }
        }
    }
    for ($i = 0; $i -lt $fields.Count; $i++) {
        if ($i -eq 0) { $lines += "      - $($fields[$i])" } else { $lines += "        $($fields[$i])" }
    }
    return ($lines -join "`n")
}

# A build of the map ("builds": a workflow of no Azure resource: build, test, pack...): its triggers,
# manual-run inputs and jobs, written out as they are.
function Get-BuildWorkflow($Build, [string[]]$EnvBranches, [string[]]$EnvNames) {
    $out = New-Object Collections.Generic.List[string]
    $out.Add("$generatedMark from infra/infra.map.json (the build $($Build.workflow)): don't edit it here.")
    $out.Add('# Change "builds" in the map, then run .\infra\generate.ps1.')
    $out.Add('#')
    foreach ($a in @($Build.about | Where-Object { $_ })) { $out.Add("# $a") }
    $out.Add("name: $($Build.name)")
    $out.Add('')
    $out.Add('on:')
    # Its branches: named ones, and "{environments}" for the environments' deploy branches.
    $branches = @()
    foreach ($b in @($Build.branches | Where-Object { $_ })) { if ($b -eq '{environments}') { $branches += $EnvBranches } else { $branches += [string]$b } }
    $branches = @($branches | Select-Object -Unique)
    if ($branches.Count) {
        $out.Add('  push:')
        $out.Add('    branches: [' + ((@($branches | ForEach-Object { Get-YamlQuoted $_ })) -join ', ') + ']')
        $paths = @($Build.paths | Where-Object { $_ }) + ".github/workflows/$($Build.workflow)"
        $out.Add('    paths:')
        foreach ($p in $paths) {
            if ($p -is [string]) { $out.Add("      - $(Get-YamlQuoted $p)") }
            else { foreach ($c in @($p.comment | Where-Object { $_ })) { $out.Add("      # $c") }; $out.Add("      - $(Get-YamlQuoted $p.path)") }
        }
    }
    $out.Add('  workflow_dispatch:')
    if ($Build.inputs) {
        $out.Add('    inputs:')
        foreach ($i in $Build.inputs.PSObject.Properties) {
            $out.Add("      $($i.Name):")
            if ($i.Value.description) { $out.Add("        description: $(Get-YamlQuoted ([string]$i.Value.description))") }
            if ($i.Value.type) { $out.Add("        type: $($i.Value.type)") }
            if ($i.Value.options) { $out.Add('        options: [' + ((@($i.Value.options) | ForEach-Object { [string]$_ }) -join ', ') + ']') }
            if ($null -ne $i.Value.default) { $out.Add("        default: $(Get-YamlValue $i.Value.default)") }
        }
    }
    if ($Build.permissions) {
        $out.Add('')
        $out.Add('permissions:')
        foreach ($p in $Build.permissions.PSObject.Properties) { $out.Add("  $($p.Name): $($p.Value)") }
    }
    $out.Add('')
    $out.Add('jobs:')
    $first = $true
    foreach ($j in @($Build.jobs | Where-Object { $_ })) {
        if (-not $first) { $out.Add('') }
        $first = $false
        $out.Add("  $($j.id):")
        if ($j.name) { $out.Add("    name: $($j.name)") }
        $needs = @($j.needs | Where-Object { $_ })
        if ($needs.Count -eq 1) { $out.Add("    needs: $($needs[0])") } elseif ($needs.Count) { $out.Add('    needs: [' + ($needs -join ', ') + ']') }
        if ($j.if) { $out.Add("    if: $($j.if)") }
        $out.Add("    runs-on: $($j.runsOn)")
        if ($j.permissions) {
            $out.Add('    permissions:')
            foreach ($p in $j.permissions.PSObject.Properties) { $out.Add("      $($p.Name): $($p.Value)") }
        }
        $out.Add('    steps:')
        $steps = Get-StepsYaml $j.steps ''
        if ($steps) { $out.Add($steps) }
    }
    return (($out -join "`n") + "`n")
}
function Get-StepsYaml($Steps, [string]$If) { return ((@($Steps | Where-Object { $_ }) | ForEach-Object { Get-StepYaml $_ $If }) -join "`n") }

function Get-Workflows {
    $out = [ordered]@{}
    $envNames = @($naming.environments.PSObject.Properties | ForEach-Object { [string]$_.Value })
    $defaultEnv = [string]$naming.environments.prod
    if (-not $defaultEnv) { $defaultEnv = $envNames[0] }
    $envBranches = @(Get-EnvBranches)
    foreach ($d in @($defs | Where-Object { $_.deploy })) {
        $dep = $d.deploy
        $template = Join-Path $infra "catalog\workflows\$($d.kind).yml"
        if (-not (Test-Path $template)) { Fail "$($d.key): no catalog/workflows/$($d.kind).yml for its deploy" }
        if (-not $dep.workflow) { Fail "$($d.key): deploy has no workflow (its file name in .github/workflows)" }
        $v = @{ key = $d.key; name = [string]$dep.name }
        $f = @{}
        $v.about = ((@($dep.about | Where-Object { $_ }) | ForEach-Object { "# $_" }) -join "`n")
        if (-not $v.about) { $v.about = "# $($d.title): $($dep.source) -> $($d.kind) $($d.key)" }
        # The trigger: the source folder, the other paths, the workflow itself; the branches.
        $paths = @()
        if ($dep.source) { $paths += "$($dep.source)/**" }
        foreach ($p in @($dep.paths | Where-Object { $_ })) { $paths += $p }
        $paths += ".github/workflows/$($dep.workflow)"
        $v.paths = ((@($paths | ForEach-Object {
                        if ($_ -is [string]) { "      - $(Get-YamlQuoted $_)" }
                        else { @(@($_.comment | Where-Object { $_ }) | ForEach-Object { "      # $_" }) + "      - $(Get-YamlQuoted $_.path)" -join "`n" }
                    })) -join "`n")
        if ($dep.everyBranch) {
            $v.branches = "['**']"
            $v.branchesNote = ' # every branch (its tests); deploys only from an environment''s branch (route)'
            $f.push = $true
        } else {
            $v.branches = '[' + ((@($envBranches | ForEach-Object { Get-YamlQuoted $_ })) -join ', ') + ']'
            $v.branchesNote = ' # the environments'' deploy branches (infra/environments/*.json)'
            $f.push = [bool]$envBranches.Count
        }
        $v.environments = '[' + ($envNames -join ', ') + ']'
        $v.defaultEnvironment = $defaultEnv
        $v.beforeBuild = ''
        $v.afterDeploy = ''
        if ($d.kind -eq 'staticWebApp') {
            $f.node = [bool]$dep.node
            $v.node = [string]$dep.node
            $v.source = [string]$dep.source
            $v.nodeComment = ((@($dep.nodeComment | Where-Object { $_ }) | ForEach-Object { "      # $_" }) -join "`n")
            $v.beforeBuild = Get-StepsYaml $dep.beforeBuild ''
            $v.buildStep = ''
            if ($dep.build) {
                $b = $dep.build
                if (-not $b.workingDirectory) { $b | Add-Member -NotePropertyName workingDirectory -NotePropertyValue ([string]$dep.source) -Force }
                $v.buildStep = Get-StepYaml $b ''
            }
            $token = @($map.github.tokenSecrets | Where-Object { $_ -and $_.resource -eq $d.key }) | Select-Object -First 1
            if (-not $token) { Fail "$($d.key): no github.tokenSecrets entry (its deployment token)" }
            $v.tokenExpr = "secrets.$($token.name)"
            if ($dep.tokenFallback) { $v.tokenExpr += " || secrets.$($dep.tokenFallback)" }
            $v.app = [string]$dep.app
            $v.api = [string]$dep.api
            $v.appComment = ''
            $v.apiComment = ''
            if ($dep.appComment) { $v.appComment = " # $($dep.appComment)" }
            if ($dep.apiComment) { $v.apiComment = " # $($dep.apiComment)" }
            $v.afterDeploy = Get-StepsYaml $dep.afterDeploy ''
        } else {
            # The app's name in the GitHub environment: the variable whose value is {<key>.name}.
            $var = @($map.github.variables.PSObject.Properties | Where-Object { [string]$_.Value -eq "{$($d.key).name}" }) | Select-Object -First 1
            if (-not $var) { Fail "$($d.key): no github.variables entry with {$($d.key).name} (the app's name for its workflow)" }
            $v.appVar = $var.Name
            $dotnet = [string]$dep.dotnet
            if (-not $dotnet -and $d.runtime) { $dotnet = ([string]$d.runtime).Split('|')[-1] + '.x' }
            $v.dotnet = $dotnet
            $v.project = [string]$dep.project
            if (-not $v.project) { $v.project = [string]$dep.source }
            $v.publishArgs = ''
            if ($dep.publishArgs) { $v.publishArgs = " $($dep.publishArgs)" }
            $f.test = [bool]$dep.test
            $v.testStep = ''
            if ($dep.test) { $v.testStep = Get-StepYaml $dep.test '' }
            $v.needs = 'route'
            if ($f.test) { $v.needs = 'test, route' }
            $v.beforeBuild = Get-StepsYaml $dep.beforeBuild 'steps.env.outputs.ready'
            $v.afterDeploy = Get-StepsYaml $dep.afterDeploy 'steps.env.outputs.ready'
            if ($d.kind -eq 'functionApp') {
                $host_ = @(Get-Links $d.key 'host') | Select-Object -First 1
                $f.flex = $host_ -and (Get-Def $host_.to).kind -eq 'flexPlan'
            }
        }
        $out[[string]$dep.workflow] = (Get-Fragment $d.kind $v $f $template) + "`n"
    }
    # The builds (workflows of no Azure resource).
    foreach ($b in @($map.builds | Where-Object { $_ })) {
        if (-not $b.workflow) { Fail 'a build has no workflow (its file name in .github/workflows)' }
        if ($out.Contains([string]$b.workflow)) { Fail "two workflows named $($b.workflow)" }
        $out[[string]$b.workflow] = Get-BuildWorkflow $b $envBranches $envNames
    }
    return $out
}

$text = Get-Bicep
$workflows = Get-Workflows
$utf8 = New-Object Text.UTF8Encoding $false
$now = ''
if (Test-Path $target) { $now = (Get-Content $target -Raw -Encoding UTF8).Replace("`r`n", "`n") }
# What differs: main.bicep, a workflow, or a generated workflow of an app that isn't in the map any more.
$stale = @()
if ($now -ne $text) { $stale += $map.project.template }
foreach ($w in $workflows.Keys) {
    $file = Join-Path $workflowDir $w
    $have = ''
    if (Test-Path $file) { $have = (Get-Content $file -Raw -Encoding UTF8).Replace("`r`n", "`n") }
    # Never over a workflow written by hand (only a generated one is replaced).
    if ($have -and -not $have.StartsWith($generatedMark)) { Fail ".github/workflows/$w is a workflow written by hand: give the app's deploy another workflow name in the map (or move that file away)" }
    if ($have -ne $workflows[$w]) { $stale += ".github/workflows/$w" }
}
$orphans = @(Get-ChildItem $workflowDir -Filter '*.yml' -ErrorAction SilentlyContinue | Where-Object {
        -not $workflows.Contains($_.Name) -and (Get-Content $_.FullName -TotalCount 1) -like "$generatedMark*" })
foreach ($o in $orphans) { $stale += ".github/workflows/$($o.Name) (no app deploys with it any more)" }

if ($Check) {
    if (-not $stale.Count) { if (-not $Quiet) { Write-Host "$($map.project.template) and the workflows are what the map makes." -ForegroundColor Green }; exit 0 }
    if (-not $Quiet) { Write-Host "Not what the map makes: $($stale -join ', '). Run .\infra\generate.ps1" -ForegroundColor Yellow }
    exit 1
}
if (-not $stale.Count) { if (-not $Quiet) { Write-Host "$($map.project.template) and the workflows: no change." -ForegroundColor Green }; exit 0 }
if ($now -ne $text) {
    [IO.File]::WriteAllText($target, $text, $utf8)
    if (-not $Quiet) { Write-Host "$($map.project.template) written from the map. A dry run shows what changes in Azure: .\infra\azure-setup.ps1 -DryRun" -ForegroundColor Green }
}
if ($workflows.Count) { New-Item -ItemType Directory -Force -Path $workflowDir | Out-Null }
foreach ($w in $workflows.Keys) {
    $file = Join-Path $workflowDir $w
    $have = ''
    if (Test-Path $file) { $have = (Get-Content $file -Raw -Encoding UTF8).Replace("`r`n", "`n") }
    if ($have -eq $workflows[$w]) { continue }
    [IO.File]::WriteAllText($file, $workflows[$w], $utf8)
    if (-not $Quiet) { Write-Host ".github/workflows/$w written from the map (commit it: GitHub runs it from the branch)" -ForegroundColor Green }
}
foreach ($o in $orphans) {
    Remove-Item $o.FullName
    if (-not $Quiet) { Write-Host ".github/workflows/$($o.Name) deleted (no app deploys with it any more)" -ForegroundColor Green }
}
exit 0

#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyAzure  -  route.ps1                                                ║
#  ║   Which environment a workflow run deploys to                            ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyAzure  -  https://github.com/netmedia/lazyazure          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
Which GitHub environment a workflow run deploys to (the deploy workflows in .github/workflows): a manual
run's choice, else the environment whose infra/environments/<env>.json names the pushed branch
("branch", asked by infra/azure-setup.ps1). Before production has its file, the production branch
still deploys to production. Prints environment=<name> (empty = no deploy) for $GITHUB_OUTPUT.

  ./infra/route.ps1 -Branch <branch> [-Chosen <environment>]
#>
param(
    [string]$Branch = '',
    [string]$Chosen = ''
)

$ErrorActionPreference = 'Stop'
$names = (Get-Content (Join-Path $PSScriptRoot 'naming.json') -Raw -Encoding UTF8 | ConvertFrom-Json).environments
$dir = Join-Path $PSScriptRoot 'environments'
$files = @()
if (Test-Path $dir) { $files = @(Get-ChildItem $dir -Filter '*.json') }
$byBranch = @(foreach ($f in $files) {
        if ((Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).branch -eq $Branch) { $names.($f.BaseName) }
    })
$prodSetUp = @($files | Where-Object { $_.Name -eq 'prod.json' }).Count -gt 0

$environment = ''
if ($Chosen) { $environment = $Chosen }
elseif ($byBranch.Count) { $environment = $byBranch[0] }
elseif (-not $prodSetUp -and $Branch -eq 'production') { $environment = 'production' }
"environment=$environment"

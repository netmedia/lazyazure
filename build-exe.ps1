#Requires -Version 5.1

#  ╔══════════════════════════════════════════════════════════════════════════╗
#  ║   LazyAzure  -  build-exe.ps1                                            ║
#  ║   Builds lazyazure.exe and initintoproject.exe (launchers of the .ps1)   ║
#  ║                                                                          ║
#  ║   Author  : Netmedia                                                     ║
#  ║   Web     : https://netmedia.agency                                      ║
#  ║   Email   : netmedia@netmedia.hr                                         ║
#  ║   Product : LazyAzure  -  https://github.com/netmedia/lazyazure          ║
#  ╚══════════════════════════════════════════════════════════════════════════╝

<#
.SYNOPSIS
    Builds lazyazure.exe and initintoproject.exe: launchers of the .ps1 files of the same name.

.AUTHOR
    Netmedia  |  https://netmedia.agency  |  netmedia@netmedia.hr

.DESCRIPTION
    Each .exe starts the PowerShell script of the same name next to it (lazyazure.exe -> lazyazure.ps1)
    with every argument, in the same console, and returns its exit code. The .ps1 files stay the program:
    a change to them needs no new build. Rebuild only when launcher\launcher.cs or the version changes.

    Compiled with the C# compiler that comes with Windows (.NET Framework 4); no SDK, no packages. The
    version (file properties: Netmedia, LazyAzure) is infra\kit.json's.

      launcher\launcher.cs  ->  infra\lazyazure.exe      (next to infra\lazyazure.ps1)
                            ->  initintoproject.exe      (next to initintoproject.ps1)

.PARAMETER Help
    Display the usage guide and exit.

.EXAMPLE
    .\build-exe.ps1

.NOTES
    LazyAzure is a Netmedia product: https://netmedia.agency, netmedia@netmedia.hr,
    https://github.com/netmedia/lazyazure.
#>
[CmdletBinding()]
param(
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$manifest = Get-Content (Join-Path $root 'infra\kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json

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
    $title = 'LazyAzure  -  build-exe.ps1'
    Write-Host ''
    Write-Host "  $([char]0x256D)$hLine$([char]0x256E)" -ForegroundColor Cyan
    Row ''
    Row "$esc[1m$title$esc[0m" $title 'Cyan'
    Row 'Builds lazyazure.exe and initintoproject.exe' -color 'White'
    Row ''
    Row "by Netmedia  |  LazyAzure $($manifest.version)" -color 'DarkGray'
    Row 'https://netmedia.agency  |  netmedia@netmedia.hr' -color 'DarkGray'
    Row ''
    Write-Host "  $([char]0x2570)$hLine$([char]0x256F)" -ForegroundColor Cyan
    Write-Host ''
}

Show-Author
if ($Help) {
    Write-Host '  USAGE' -ForegroundColor White
    Write-Host '    .\build-exe.ps1' -ForegroundColor Green
    Write-Host ''
    Write-Host '    launcher\launcher.cs -> infra\lazyazure.exe and initintoproject.exe. Each starts the .ps1 of' -ForegroundColor DarkGray
    Write-Host '    the same name next to it; the .ps1 files stay the program (no rebuild after changing them).' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { Write-Host '  ERROR: no C# compiler of .NET Framework 4 (it comes with Windows).' -ForegroundColor Red; exit 1 }

# The version of kit.json in the file properties (a.b.c -> a.b.c.0).
$version = ([string]$manifest.version -replace '[^0-9.].*$', '')
while (($version.Split('.')).Count -lt 4) { $version += '.0' }
$source = Join-Path ([IO.Path]::GetTempPath()) ('lazyazure-launcher-' + [guid]::NewGuid().ToString('N') + '.cs')
$text = (Get-Content (Join-Path $root 'launcher\launcher.cs') -Raw -Encoding UTF8) -replace 'public const string Version = "[^"]*";', "public const string Version = `"$version`";"
[IO.File]::WriteAllText($source, $text, (New-Object Text.UTF8Encoding $false))

$code = 0
try {
    foreach ($out in @((Join-Path $root 'infra\lazyazure.exe'), (Join-Path $root 'initintoproject.exe'))) {
        $result = & $csc /nologo /optimize+ /target:exe /platform:anycpu "/out:$out" $source 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host "  $([char]0x2717) $(Split-Path $out -Leaf): $result" -ForegroundColor Red; $code = 1; continue }
        Write-Host "  $([char]0x2713) $((Resolve-Path $out -Relative)) ($version, $([int]((Get-Item $out).Length / 1KB)) KB)" -ForegroundColor Green
    }
} finally { Remove-Item $source -ErrorAction SilentlyContinue }
if (-not $code) {
    Write-Host ''
    Write-Host '  Each .exe starts the .ps1 of the same name next to it: keep them together (kit.json lists both).' -ForegroundColor DarkGray
    Write-Host ''
}
exit $code

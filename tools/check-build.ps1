#requires -Version 5.1
<#
.SYNOPSIS
    Check that a built Falcor tree actually exposes our research passes.

.DESCRIPTION
    Encodes the plugin contract as assertions, so "my pass does not show up in
    Mogwai" can be diagnosed without clicking around:

        <bin>/Mogwai.exe                        exists
        <bin>/Falcor.dll                        exists
        <bin>/plugins/<Name>.dll                exists for every package in passes.txt
        <bin>/plugins/plugins.json              contains <Name>
        <bin>/shaders/RenderPasses/<Name>/*     at least one .slang deployed

    Exit code 1 when any check fails.

.EXAMPLE
    pwsh -File tools\check-build.ps1

.EXAMPLE
    pwsh -File tools\check-build.ps1 -Config Debug
#>
[CmdletBinding()]
param(
    [string]$Config = 'RelWithDebInfo'
)

. "$PSScriptRoot\env.ps1"

$binDir = Get-FalcorBinDir -Config $Config
$pluginDir = Join-Path $binDir 'plugins'
$shaderRoot = Join-Path $binDir 'shaders\RenderPasses'
$failures = 0

Write-Host ''
Write-Host "Eidolon build check ($Config)" -ForegroundColor Cyan
Write-Host "  bin: $binDir"
Write-Host ''

function Check {
    param([bool]$Condition, [string]$Name, [string]$Detail = '')
    if ($Condition) {
        Write-Host ("  [OK  ] {0,-34} {1}" -f $Name, $Detail) -ForegroundColor Green
    }
    else {
        Write-Host ("  [FAIL] {0,-34} {1}" -f $Name, $Detail) -ForegroundColor Red
        $script:failures++
    }
}

# 1. Executables / framework library.
$mogwai = Join-Path $binDir 'Mogwai.exe'
Check (Test-Path $mogwai) 'Mogwai.exe' $(if (Test-Path $mogwai) { $mogwai } else { "not found (build with: tools\build.ps1 -Configure)" })
Check (Test-Path (Join-Path $binDir 'Falcor.dll')) 'Falcor.dll' $(if (Test-Path (Join-Path $binDir 'Falcor.dll')) { 'present' } else { 'missing' })

# 2. Plugin library per registered package.
$registry = $script:PassRegistry
$packages = @()
if (Test-Path $registry) {
    $packages = Get-Content $registry -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        Sort-Object
}

if ($packages.Count -eq 0) {
    Write-Warn "No packages registered in $registry"
}
else {
    Write-Host ''
    Write-Host '  packages from research/passes.txt:' -ForegroundColor DarkGray
}

foreach ($pkg in $packages) {
    $dll = Join-Path $pluginDir "$pkg.dll"
    Check (Test-Path $dll) "plugin: $pkg" $(if (Test-Path $dll) { $dll } else { 'DLL missing - was the CMakeLists change re-configured?' })

    $shaderDir = Join-Path $shaderRoot $pkg
    $slangs = @()
    if (Test-Path $shaderDir) {
        $slangs = Get-ChildItem $shaderDir -File -Include '*.slang', '*.slangh', '*.hlsl', '*.hlsli' -ErrorAction SilentlyContinue
    }
    Check ($slangs.Count -gt 0) "shaders: $pkg" $(if ($slangs.Count -gt 0) { "$($slangs.Count) file(s) in $shaderDir" } else { "nothing deployed to $shaderDir (target_copy_shaders?)" })
}

# 3. plugins.json membership (this is what PluginManager::loadAllPlugins reads).
$pluginsJson = Join-Path $pluginDir 'plugins.json'
if (Test-Path $pluginsJson) {
    $jsonText = [System.IO.File]::ReadAllText($pluginsJson)
    Write-Host ''
    foreach ($pkg in $packages) {
        Check ($jsonText -match [regex]::Escape("`"$pkg`"")) "plugins.json: $pkg" 'listed' 
    }
}
else {
    Write-Host ''
    Check $false 'plugins.json' "missing at $pluginsJson (CMake generates it after configure)"
}

Write-Host ''
if ($failures -eq 0) {
    Write-Ok 'build contract satisfied - Mogwai should discover the passes above.'
    exit 0
}
Write-Fail "$failures check(s) failed. See docs/05-troubleshooting.md (runtime section)."
exit 1

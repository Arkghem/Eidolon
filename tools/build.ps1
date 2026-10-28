#requires -Version 5.1
<#
.SYNOPSIS
    Configure and build the vendored Falcor tree (optionally only our plugins).

.DESCRIPTION
    Wraps the whole build path so that nobody has to remember the preset names:

      * initializes the submodules (first run only),
      * pulls the packman dependencies via Falcor's setup.bat (first run only),
      * re-syncs the render-pass overlay when research/passes.txt changed,
      * configures with the windows-vs2022 preset (USD disabled),
      * builds the requested targets.

    Defaults to RelWithDebInfo: symbols for RenderDoc, near-Release performance
    for measurements. Never measure with a Debug build.

.EXAMPLE
    # full build (first time, ~40-90 min)
    pwsh -File tools\build.ps1 -Configure

.EXAMPLE
    # rebuild only my plugin after a C++ change
    pwsh -File tools\build.ps1 -Target HelloPT
#>
[CmdletBinding()]
param(
    [string]$Config = 'RelWithDebInfo',
    [string]$Preset = 'windows-vs2022',
    [string[]]$Target = @(),
    [switch]$Configure,
    [switch]$SkipSync,
    [switch]$SkipSetup
)

. "$PSScriptRoot\env.ps1"

Assert-Path $script:FalcorDir 'vendor/falcor is missing. Run git submodule update --init --recursive'

$buildDir = Join-Path $script:FalcorDir "build\$Preset"

# -----------------------------------------------------------------------------
# 1. Submodules + packman dependencies
# -----------------------------------------------------------------------------

if (-not $SkipSetup) {
    $pybind = Join-Path $script:FalcorDir 'external\pybind11\CMakeLists.txt'
    if (-not (Test-Path $pybind)) {
        Write-Step 'Initializing Falcor submodules (first run, this downloads a few hundred MB)...'
        Invoke-Native git @('-C', $script:FalcorDir, 'submodule', 'update', '--init', '--recursive') | Out-Null
    }

    $packmanDir = Join-Path $script:FalcorDir 'tools\.packman'
    if (-not (Test-Path $packmanDir)) {
        Write-Step 'Pulling packman dependencies (first run, several GB: cmake, ninja, python, slang, media...)...'
        $setupBat = Join-Path $script:FalcorDir 'setup.bat'
        Assert-Path $setupBat 'Falcor setup.bat is missing - unexpected Falcor layout.'
        Invoke-Native $setupBat @() | Out-Null
    }
}

# -----------------------------------------------------------------------------
# 2. Overlay injection
# -----------------------------------------------------------------------------

if (-not $SkipSync) {
    $syncScript = Join-Path $PSScriptRoot 'sync-passes.ps1'
    & $syncScript
    if (-not $?) { throw 'sync-passes.ps1 failed.' }
}

# -----------------------------------------------------------------------------
# 3. Configure
# -----------------------------------------------------------------------------

$cacheFile = Join-Path $buildDir 'CMakeCache.txt'
if ($Configure -or -not (Test-Path $cacheFile)) {
    Write-Step "Configuring preset '$Preset' (FALCOR_ENABLE_USD=OFF)"
    Invoke-Native cmake @('--preset', $Preset, '-DFALCOR_ENABLE_USD=OFF') $script:FalcorDir | Out-Null
}
else {
    Write-Skip "configure (build tree already exists; pass -Configure to force)" | Out-Null
}

# -----------------------------------------------------------------------------
# 4. Build
# -----------------------------------------------------------------------------

$buildArgs = @('--build', $buildDir, '--config', $Config)
if ($Target.Count -gt 0) {
    foreach ($t in $Target) { $buildArgs += @('--target', $t) }
}

Write-Step "Building ($Config): $(if ($Target.Count) { $Target -join ', ' } else { 'default target' })"
Invoke-Native cmake $buildArgs | Out-Null

# -----------------------------------------------------------------------------
# 5. Report
# -----------------------------------------------------------------------------

$binDir = Get-FalcorBinDir -Config $Config
$mogwai = Join-Path $binDir 'Mogwai.exe'
Write-Host ''
Write-Ok "Build finished."
Write-Host "   bin      : $binDir"
if (Test-Path $mogwai) { Write-Host "   Mogwai   : $mogwai" }
$pluginDir = Get-PluginDir -Config $Config
if (Test-Path $pluginDir) {
    $ours = Get-ChildItem $pluginDir -Filter '*.dll' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($Target.Count -gt 0) {
        foreach ($t in $Target) {
            $dll = Join-Path $pluginDir "$t.dll"
            if (Test-Path $dll) { Write-Ok "plugin: $dll" } else { Write-Fail "expected plugin DLL missing: $dll" }
        }
    }
}

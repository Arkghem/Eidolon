#requires -Version 5.1
<#
.SYNOPSIS
    Run one experiment from its configs/*.json, optionally capturing a frame.

.DESCRIPTION
    An experiment directory owns its render graph and its numeric settings:

        experiments/<NNNN-slug>/
            configs/default.json   <- resolution, graph, scene, extra args
            graphs/*.py
            results/               <- gitignored output

    This script reads that config and hands it to tools/run-mogwai.ps1 (or
    tools/capture.ps1 with -Capture), so tweaking a run never means editing a
    command line by hand.

.EXAMPLE
    pwsh -File tools\run-experiment.ps1 -Experiment 0001-hello-pass

.EXAMPLE
    pwsh -File tools\run-experiment.ps1 -Experiment 0001-hello-pass -Capture -Frame 30 -Mode cmd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Experiment,
    [string]$ConfigName = 'default.json',
    [string]$Config = 'RelWithDebInfo',
    [switch]$Headless,
    [switch]$Capture,
    [ValidateSet('interactive', 'cmd')][string]$Mode = 'interactive',
    [int]$Frame = -1,
    [switch]$DryRun
)

. "$PSScriptRoot\env.ps1"

$expDir = Join-Path $script:EidolonRoot "experiments\$Experiment"
Assert-Path $expDir "experiments\$Experiment does not exist. Create it with: tools\new-experiment.ps1 <slug>"

$configPath = Join-Path (Join-Path $expDir 'configs') $ConfigName
Assert-Path $configPath "Missing config $configPath"

$cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Resolve-ExpPath {
    param([string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative)) { return $null }
    $p = Join-Path $expDir $Relative
    if (Test-Path $p) { return (Resolve-Path $p).Path }
    return $Relative # let the caller decide (e.g. media paths)
}

$graphPath = Resolve-ExpPath $cfg.graph
if (-not $graphPath) { throw "config '$ConfigName' has no 'graph' entry." }

$width = if ($cfg.width) { [int]$cfg.width } else { 1920 }
$height = if ($cfg.height) { [int]$cfg.height } else { 1080 }
$sceneValue = if ($cfg.scene) { [string]$cfg.scene } else { $null }
if ($sceneValue) {
    $resolvedScene = Resolve-ExpPath $sceneValue
    if ($resolvedScene) { $sceneValue = $resolvedScene }
}
$tag = if ($cfg.tag) { [string]$cfg.tag } else { $Experiment }
$extra = @()
if ($cfg.extraArgs) { $extra = @($cfg.extraArgs) }

$isHeadless = $Headless -or [bool]$cfg.headless

Write-Skip "experiment: $Experiment"
Write-Skip "config    : $configPath"
Write-Skip "graph     : $graphPath"
if ($sceneValue) { Write-Skip "scene     : $sceneValue" }

if ($Capture) {
    $captureMode = if ($PSBoundParameters.ContainsKey('Mode')) { $Mode } elseif ($cfg.capture -and $cfg.capture.mode) { [string]$cfg.capture.mode } else { 'interactive' }
    $captureFrame = if ($PSBoundParameters.ContainsKey('Frame')) { $Frame } elseif ($cfg.capture -and $null -ne $cfg.capture.frame) { [int]$cfg.capture.frame } else { -1 }

    $captureArgs = @{
        Experiment = $Experiment
        Graph      = $graphPath
        Mode       = $captureMode
        Frame      = $captureFrame
        Config     = $Config
        Width      = $width
        Height     = $height
        ExtraArgs  = $extra
    }
    if ($sceneValue) { $captureArgs.Scene = $sceneValue }
    if ($DryRun) { $captureArgs.DryRun = $true }
    & (Join-Path $PSScriptRoot 'capture.ps1') @captureArgs
    exit $LASTEXITCODE
}

$runArgs = @{
    Graph     = $graphPath
    Width     = $width
    Height    = $height
    Config    = $Config
    Tag       = $tag
    ExtraArgs = $extra
}
if ($sceneValue) { $runArgs.Scene = $sceneValue }
if ($isHeadless) { $runArgs.Headless = $true }
if ($DryRun) { $runArgs.DryRun = $true }

& (Join-Path $PSScriptRoot 'run-mogwai.ps1') @runArgs
exit $LASTEXITCODE

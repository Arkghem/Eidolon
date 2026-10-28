#requires -Version 5.1
<#
.SYNOPSIS
    Run Mogwai with a render graph, optionally with a scene and headless.

.DESCRIPTION
    Takes care of the details that bite people:

      * runs with the working directory set to the Falcor bin folder (Falcor
        resolves plugins/shaders/data relative to the executable),
      * exports FALCOR_MEDIA_FOLDERS so assets/ is visible to scene loading,
      * writes the Falcor log to out/logs/,
      * after the run, collects any screenshots dropped into <bin>\Screenshots
        into out/frames/<tag>/.

.EXAMPLE
    pwsh -File tools\run-mogwai.ps1 -Graph experiments\0001-hello-pt\graphs\hello_pt.py -Scene media\Arcade\Arcade.pyscene

.EXAMPLE
    pwsh -File tools\run-mogwai.ps1 -Graph experiments\0001-hello-pt\graphs\hello_pt.py -Headless -Tag hello -ExtraArgs '--use-cache'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Graph,
    [string]$Scene,
    [switch]$Headless,
    [int]$Width = 1920,
    [int]$Height = 1080,
    [string]$Config = 'RelWithDebInfo',
    [string]$Tag = 'adhoc',
    [string]$LogFile,
    [string[]]$ExtraArgs = @(),
    [switch]$DryRun
)

. "$PSScriptRoot\env.ps1"

# -----------------------------------------------------------------------------
# Resolve paths
# -----------------------------------------------------------------------------

function Resolve-ExistingPath {
    param([string]$Path, [string]$What)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        Assert-Path $Path "$What path was given as absolute and does not exist."
        return (Resolve-Path $Path).Path
    }
    $fromCwd = Join-Path (Get-Location).Path $Path
    if (Test-Path $fromCwd) { return (Resolve-Path $fromCwd).Path }
    $fromRoot = Join-Path $script:EidolonRoot $Path
    if (Test-Path $fromRoot) { return (Resolve-Path $fromRoot).Path }
    throw "Cannot find $What '$Path' (looked in cwd and $($script:EidolonRoot))."
}

$binDir = Get-FalcorBinDir -Config $Config
$mogwai = Join-Path $binDir 'Mogwai.exe'
if (-not (Test-Path $mogwai)) {
    if ($DryRun) {
        Write-Warn "Mogwai is not built yet ($mogwai). -DryRun prints the command line anyway."
    }
    else {
        throw "Mogwai is not built for config '$Config' ($mogwai). Run: tools\build.ps1 -Configure"
    }
}

$graphPath = Resolve-ExistingPath -Path $Graph -What 'render graph'

$sceneArg = $null
if ($Scene) {
    if (Test-Path $Scene) { $sceneArg = (Resolve-Path $Scene).Path }
    elseif (Test-Path (Join-Path $script:EidolonRoot $Scene)) { $sceneArg = (Resolve-Path (Join-Path $script:EidolonRoot $Scene)).Path }
    else { $sceneArg = $Scene } # let Falcor resolve it against media folders
}

if (-not $LogFile) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile = Join-Path $script:EidolonRoot "out\logs\mogwai-$Tag-$stamp.log"
}
$logPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)
$logDir = Split-Path -Parent $logPath
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$media = Set-FalcorMediaFolders
if ($media) { Write-Skip "FALCOR_MEDIA_FOLDERS=$media" }

# -----------------------------------------------------------------------------
# Compose the command line
# -----------------------------------------------------------------------------

$argList = New-Object System.Collections.Generic.List[string]
$argList.Add('-s'); $argList.Add($graphPath)
if ($sceneArg) { $argList.Add('-S'); $argList.Add($sceneArg) }
$argList.Add('--width'); $argList.Add([string]$Width)
$argList.Add('--height'); $argList.Add([string]$Height)
$argList.Add('--logfile'); $argList.Add($logPath)
$argList.Add('--verbosity'); $argList.Add('4')
if ($Headless) { $argList.Add('--headless') }
foreach ($a in $ExtraArgs) { $argList.Add($a) }

Write-Step "Mogwai ($Config, $(if ($Headless) { 'headless' } else { 'windowed' }))"
Write-Host "   graph : $graphPath" -ForegroundColor DarkGray
if ($sceneArg) { Write-Host "   scene : $sceneArg" -ForegroundColor DarkGray }
Write-Host "   log   : $logPath" -ForegroundColor DarkGray
Write-Host "   cmd   : `"$mogwai`" $($argList -join ' ')" -ForegroundColor DarkGray

if ($DryRun) { return }

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------

$startTime = Get-Date
$exitCode = 0
$argArray = @($argList)
Push-Location $binDir
try {
    & $mogwai @argArray
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

# -----------------------------------------------------------------------------
# Collect screenshots (F12 in Mogwai) if Falcor dropped any into the bin folder
# -----------------------------------------------------------------------------

$frameDir = Join-Path $script:EidolonRoot "out\frames\$Tag"
foreach ($name in @('Screenshots', 'screenshots')) {
    $shotDir = Join-Path $binDir $name
    if (-not (Test-Path $shotDir)) { continue }
    $newShots = Get-ChildItem $shotDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $startTime -and $_.Extension -in @('.png', '.jpg', '.jpeg', '.exr', '.bmp') }
    if ($newShots) {
        if (-not (Test-Path $frameDir)) { New-Item -ItemType Directory -Path $frameDir -Force | Out-Null }
        foreach ($f in $newShots) { Move-Item $f.FullName (Join-Path $frameDir $f.Name) -Force }
        Write-Ok "Collected $($newShots.Count) screenshot(s) into $frameDir"
    }
}

Write-Host ''
if ($exitCode -eq 0) { Write-Ok 'Mogwai exited normally.' }
else { Write-Fail "Mogwai exited with code $exitCode (see $logPath)." }

if (Test-Path $logPath) {
    $tail = Get-Content $logPath -Tail 15
    if ($tail) {
        Write-Host ''
        Write-Host '--- last log lines ---' -ForegroundColor DarkGray
        $tail | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
    }
}

exit $exitCode

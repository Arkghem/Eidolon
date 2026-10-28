#requires -Version 5.1
<#
.SYNOPSIS
    Capture a frame of Mogwai with RenderDoc.

.DESCRIPTION
    Falcor 9.0 no longer exposes an in-process RenderDoc API, so capture is
    always out-of-process. Two modes:

      interactive (default)
          Launches qrenderdoc and prints the exact "Launch Application"
          parameters. You press F12 (or click the capture button) inside Mogwai
          and then save the .rdc into out\captures\<experiment>\.

      cmd
          Fully scripted: renderdoccmd capture --wait-for-exit ... This needs the
          application to terminate on its own after the capture, so it is meant
          for runs with a self-terminating script. Use -TimeoutSeconds to bound
          the wait; the script then stops the Mogwai processes it spawned.

    Every successful capture writes a manifest.json next to the .rdc recording
    the commit, graph, scene and versions, so a capture stays interpretable.

.EXAMPLE
    pwsh -File tools\capture.ps1 -Experiment 0001-hello-pass -Graph experiments\0001-hello-pass\graphs\hello_pass.py -Scene media\Arcade\Arcade.pyscene

.EXAMPLE
    pwsh -File tools\capture.ps1 -Mode cmd -Experiment smoke -Graph experiments\0001-hello-pass\graphs\hello_pass.py -Frame 10 -TimeoutSeconds 90 -ExtraArgs '--headless'
#>
[CmdletBinding()]
param(
    [string]$Experiment = 'adhoc',
    [string]$Graph,
    [string]$Scene,
    [ValidateSet('interactive', 'cmd')][string]$Mode = 'interactive',
    [int]$Frame = -1,
    [string]$Config = 'RelWithDebInfo',
    [int]$Width = 1920,
    [int]$Height = 1080,
    [int]$TimeoutSeconds = 0,
    [string]$Output,
    [string[]]$ExtraArgs = @(),
    [switch]$DryRun
)

. "$PSScriptRoot\env.ps1"

# -----------------------------------------------------------------------------
# Resolve everything up front so failures happen before a GPU process starts
# -----------------------------------------------------------------------------

$binDir = Get-FalcorBinDir -Config $Config
$mogwai = Join-Path $binDir 'Mogwai.exe'
if (-not (Test-Path $mogwai)) {
    if ($DryRun) {
        Write-Warn "Mogwai is not built yet ($mogwai). -DryRun prints the command line anyway."
    }
    else {
        throw "Mogwai is not built for '$Config'. Run: tools\build.ps1 -Configure"
    }
}

$qrenderdoc = $null
foreach ($candidate in @('C:\Program Files\RenderDoc\qrenderdoc.exe')) { if (Test-Path $candidate) { $qrenderdoc = $candidate } }
if (-not $qrenderdoc) {
    $c = Get-Command qrenderdoc -ErrorAction SilentlyContinue
    if ($c) { $qrenderdoc = $c.Source }
}

$renderdoccmd = $null
foreach ($candidate in @('C:\Program Files\RenderDoc\renderdoccmd.exe')) { if (Test-Path $candidate) { $renderdoccmd = $candidate } }
if (-not $renderdoccmd) {
    $c = Get-Command renderdoccmd -ErrorAction SilentlyContinue
    if ($c) { $renderdoccmd = $c.Source }
}
if (-not $qrenderdoc -and -not $renderdoccmd) {
    if (-not $DryRun) {
        throw 'RenderDoc is not installed. Run tools\install-toolchain.ps1, or install it from https://renderdoc.org/.'
    }
    Write-Warn 'RenderDoc is not installed; -DryRun still prints the command line.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = if ($Output) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
} else {
    Join-Path $script:EidolonRoot "out\captures\$Experiment"
}
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$graphPath = $null
if ($Graph) {
    if (Test-Path $Graph) { $graphPath = (Resolve-Path $Graph).Path }
    elseif (Test-Path (Join-Path $script:EidolonRoot $Graph)) { $graphPath = (Resolve-Path (Join-Path $script:EidolonRoot $Graph)).Path }
    else { throw "Render graph not found: $Graph" }
}

$sceneArg = $Scene
if ($Scene -and (Test-Path $Scene)) { $sceneArg = (Resolve-Path $Scene).Path }

Set-FalcorMediaFolders | Out-Null

$appArgs = New-Object System.Collections.Generic.List[string]
if ($graphPath) { $appArgs.Add('-s'); $appArgs.Add($graphPath) }
if ($sceneArg) { $appArgs.Add('-S'); $appArgs.Add($sceneArg) }
$appArgs.Add('--width'); $appArgs.Add([string]$Width)
$appArgs.Add('--height'); $appArgs.Add([string]$Height)
foreach ($a in $ExtraArgs) { $appArgs.Add($a) }

$rdcPath = Join-Path $outDir ("{0}-{1}.rdc" -f $Experiment, $stamp)

# -----------------------------------------------------------------------------
# Interactive mode
# -----------------------------------------------------------------------------

if ($Mode -eq 'interactive') {
    if (-not $qrenderdoc) {
        if (-not $DryRun) { throw 'qrenderdoc not found; use -Mode cmd with renderdoccmd instead.' }
        Write-Warn 'qrenderdoc not found; printing the launch parameters anyway.'
    }

    Write-Step 'RenderDoc interactive capture'
    Write-Host ''
    Write-Host '  In qrenderdoc: File -> Launch Application, then use these values:' -ForegroundColor Yellow
    Write-Host ("    Executable  : {0}" -f $mogwai)
    Write-Host ("    Working Dir : {0}" -f $binDir)
    Write-Host ("    Arguments   : {0}" -f ($appArgs -join ' '))
    Write-Host ("    Capture file: {0}" -f $rdcPath)
    Write-Host ''
    Write-Host '  Then: F12 (or the "Trigger capture" button) -> File -> Save Capture As ...' -ForegroundColor Yellow
    Write-Host '  Tip: keep "Enable Global Hook" on in RenderDoc settings so F12 works in any launch mode.' -ForegroundColor DarkGray
    Write-Host ''
    if (-not $DryRun) { Start-Process -FilePath $qrenderdoc }
    return
}
# -----------------------------------------------------------------------------
# Automated renderdoccmd mode
# -----------------------------------------------------------------------------

if (-not $renderdoccmd) {
    if (-not $DryRun) { throw 'renderdoccmd.exe not found; install the full RenderDoc package.' }
    $renderdoccmd = 'renderdoccmd.exe'
    Write-Warn 'renderdoccmd not found; assuming a current version so the dry run can print the command.'
}
if (-not $graphPath) { throw '-Graph is required in -Mode cmd.' }

# RenderDoc versions differ in their flags; probe instead of assuming.
if (Test-Path $renderdoccmd) {
    $helpText = (& $renderdoccmd capture --help 2>&1 | Out-String)
}
else {
    $helpText = '--capture-frame --wait-for-exit --working-dir'
}
$supportsCaptureFrame = $helpText -match '--capture-frame'
$supportsWaitForExit = $helpText -match '--wait-for-exit'
$supportsWorkingDir = $helpText -match '--working-dir'

Write-Skip ("renderdoccmd: capture-frame={0} wait-for-exit={1} working-dir={2}" -f $supportsCaptureFrame, $supportsWaitForExit, $supportsWorkingDir)

$cmdArgs = New-Object System.Collections.Generic.List[string]
$cmdArgs.Add('capture')
if ($supportsWaitForExit) { $cmdArgs.Add('--wait-for-exit') }
if ($supportsWorkingDir) { $cmdArgs.Add('--working-dir'); $cmdArgs.Add($binDir) }
$cmdArgs.Add('--capture-file'); $cmdArgs.Add($rdcPath)
if ($Frame -ge 0) {
    if ($supportsCaptureFrame) { $cmdArgs.Add('--capture-frame'); $cmdArgs.Add([string]$Frame) }
    else { Write-Warn 'This renderdoccmd has no --capture-frame; capturing the first present instead.' }
}
$cmdArgs.Add($mogwai)
foreach ($a in $appArgs) { $cmdArgs.Add($a) }

Write-Step 'RenderDoc automated capture'
Write-Host ("   cmd: `"{0}`" {1}" -f $renderdoccmd, ($cmdArgs -join ' ')) -ForegroundColor DarkGray
if ($DryRun) { return }

$startTime = Get-Date
# Windows PowerShell 5.1 has no ProcessStartInfo.ArgumentList, so build one
# quoted command line. Arguments are quoted only when they contain whitespace.
$argString = ($cmdArgs | ForEach-Object {
    if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
}) -join ' '
$proc = Start-Process -FilePath $renderdoccmd -ArgumentList $argString -PassThru -NoNewWindow

$timedOut = $false
if ($TimeoutSeconds -gt 0) {
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        Write-Warn "renderdoccmd did not exit within $TimeoutSeconds s - stopping captured processes."
        # Only touch Mogwai instances that started after we launched the capture.
        Get-Process -Name Mogwai -ErrorAction SilentlyContinue |
            Where-Object { $_.StartTime -ge $startTime } |
            ForEach-Object { try { $_.Kill() } catch { } }
        try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
    }
}
else {
    $proc.WaitForExit()
}
$exitCode = if ($proc.HasExited) { $proc.ExitCode } else { -1 }

# -----------------------------------------------------------------------------
# Verify the capture + write the manifest
# -----------------------------------------------------------------------------

if (-not (Test-Path $rdcPath)) {
    Write-Fail "No capture file was produced: $rdcPath"
    throw 'RenderDoc capture failed. Re-run with -Mode interactive to see the error in the UI, and check docs/03-renderdoc.md.'
}

$sizeMb = [math]::Round((Get-Item $rdcPath).Length / 1MB, 2)
Write-Ok "capture: $rdcPath ($sizeMb MB) exit=$exitCode timedOut=$timedOut"

$commit = (& git -C $script:EidolonRoot rev-parse --short HEAD 2>$null)
if (-not $commit) { $commit = 'uncommitted' }
$falcorTag = (& git -C $script:FalcorDir describe --tags --always 2>$null)
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
$driver = if ($smi) { (& $smi.Source --query-gpu=driver_version --format=csv,noheader 2>$null) } else { 'unknown' }
$rdocVersion = if (Test-Path (Join-Path (Split-Path -Parent $renderdoccmd) 'renderdoccmd.exe')) { (Get-Item $renderdoccmd).VersionInfo.FileVersion } else { 'unknown' }

$manifest = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    experiment = $Experiment
    captureFile = (Split-Path -Leaf $rdcPath)
    captureSizeMB = $sizeMb
    frame = $Frame
    graph = $graphPath
    scene = $sceneArg
    resolution = "$Width x $Height"
    config = $Config
    repoCommit = $commit
    falcorVersion = $falcorTag
    nvidiaDriver = if ($driver) { $driver.Trim() } else { 'unknown' }
    renderdocVersion = $rdocVersion
    appArgs = ($appArgs -join ' ')
}
$manifestPath = Join-Path $outDir 'manifest.json'
# No BOM: this file is read back by Python tooling and by git diff.
Write-Utf8NoBom -Path $manifestPath -Content ($manifest | ConvertTo-Json -Depth 4)
Write-Ok "manifest: $manifestPath"

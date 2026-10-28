#requires -Version 5.1
<#
.SYNOPSIS
    One-shot setup: toolchain -> health check -> Falcor submodule -> build -> first experiment.

.DESCRIPTION
    Runs the whole P0/P1/P2 chain in order and stops at the first failure with an
    actionable message. Every step is individually re-runnable; nothing here
    depends on having run before.

    Notes:
      * The toolchain step needs administrator rights. When the shell is not
        elevated the installer relaunches itself through UAC and this script
        stops - re-run bootstrap after accepting the prompt.
      * Fetching Falcor needs network access to github.com. On a slow link this
        is the long pole (see docs/00-environment.md).

.EXAMPLE
    pwsh -File tools\bootstrap.ps1

.EXAMPLE
    # environment is already set up, just rebuild and run the smoke test
    pwsh -File tools\bootstrap.ps1 -SkipInstall
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$SkipVerify,
    [switch]$SkipBuild,
    [switch]$SkipRun,
    [switch]$SkipSubmodule
)

. "$PSScriptRoot\env.ps1"

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host ''
Write-Host 'Eidolon bootstrap' -ForegroundColor Cyan
Write-Host "  repo   : $($script:EidolonRoot)"
Write-Host "  falcor : $($script:FalcorPinnedRef) (vendored)"
Write-Host ''

$step = 0

# -----------------------------------------------------------------------------
# 1. Toolchain
# -----------------------------------------------------------------------------
$step++
if ($SkipInstall) {
    Write-Skip '[1/5] toolchain install (skipped)'
}
else {
    Write-Step "[1/5] toolchain (VS2022 BuildTools + Windows SDK 19041 + RenderDoc)"
    if (-not (Test-Elevated)) {
        Write-Warn 'The installer needs elevation and will ask through UAC.'
        & (Join-Path $PSScriptRoot 'install-toolchain.ps1')
        Write-Host ''
        Write-Warn 'Finish the UAC prompt / installer, then re-run: pwsh -File tools\bootstrap.ps1 -SkipInstall'
        exit 0
    }
    & (Join-Path $PSScriptRoot 'install-toolchain.ps1') -Elevated
    if (-not $?) { throw 'toolchain install failed.' }
}

# -----------------------------------------------------------------------------
# 2. Health check
# -----------------------------------------------------------------------------
$step++
if ($SkipVerify) {
    Write-Skip '[2/5] environment check (skipped)'
}
else {
    Write-Step '[2/5] environment check'
    & (Join-Path $PSScriptRoot 'verify.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Fail 'Blocking environment problems above. Fix them, then re-run bootstrap.'
        exit $LASTEXITCODE
    }
}

# -----------------------------------------------------------------------------
# 3. Falcor submodule
# -----------------------------------------------------------------------------
$step++
if ($SkipSubmodule) {
    Write-Skip '[3/5] falcor submodule (skipped)'
}
else {
    Write-Step "[3/5] falcor submodule @ $($script:FalcorPinnedRef)"
    if (Test-Path (Join-Path $script:FalcorDir '.git')) {
        Write-Ok 'vendor\falcor already present'
    }
    elseif (Test-Path (Join-Path $script:EidolonRoot '.gitmodules')) {
        Invoke-Native git @('-C', $script:EidolonRoot, 'submodule', 'update', '--init', '--recursive') | Out-Null
    }
    else {
        Write-Warn 'No .gitmodules yet - adding Falcor as a submodule (downloads ~40 MB + submodules).'
        Invoke-Native git @('-C', $script:EidolonRoot, 'submodule', 'add', $script:FalcorRepoUrl, 'vendor/falcor') | Out-Null
        Invoke-Native git @('-C', $script:FalcorDir, 'checkout', $script:FalcorPinnedRef) | Out-Null
        Invoke-Native git @('-C', $script:FalcorDir, 'submodule', 'update', '--init', '--recursive') | Out-Null
    }

    $head = & git -C $script:FalcorDir rev-parse --short HEAD 2>$null
    Write-Ok "vendor\falcor at $head"
}

# -----------------------------------------------------------------------------
# 4. Build
# -----------------------------------------------------------------------------
$step++
if ($SkipBuild) {
    Write-Skip '[4/5] build (skipped)'
}
else {
    Write-Step '[4/5] configure + build (first run pulls several GB of packman packages)'
    & (Join-Path $PSScriptRoot 'build.ps1') -Configure
    if (-not $?) { throw 'build failed.' }
}

# -----------------------------------------------------------------------------
# 5. Smoke test
# -----------------------------------------------------------------------------
$step++
if ($SkipRun) {
    Write-Skip '[5/5] hello experiment (skipped)'
}
else {
    Write-Step '[5/5] smoke test: experiments\0001-hello-pass'
    & (Join-Path $PSScriptRoot 'run-experiment.ps1') -Experiment '0001-hello-pass' -Headless
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'The headless run failed. Try windowed mode to see the app:'
        Write-Host '    pwsh -File tools\run-experiment.ps1 -Experiment 0001-hello-pass'
        exit $LASTEXITCODE
    }
}

Write-Host ''
Write-Ok 'bootstrap complete.'
Write-Host '   next: docs\02-workflow-realtime.md  (edit -> build -> run -> capture)'

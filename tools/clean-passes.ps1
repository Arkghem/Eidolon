#requires -Version 5.1
<#
.SYNOPSIS
    Remove the Eidolon overlay from the vendored Falcor tree.

.DESCRIPTION
    Restores vendor/falcor/Source/RenderPasses/CMakeLists.txt to its pristine
    upstream state. Run this before switching the Falcor submodule to another
    tag/release, otherwise `git checkout` inside the submodule will refuse to
    overwrite the locally modified file.

.EXAMPLE
    pwsh -File tools\clean-passes.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$FalcorDir
)

# Capture before dot-sourcing: env.ps1 assigns $script:FalcorDir, which would
# overwrite the -FalcorDir parameter (same scope, same name).
$requestedFalcorDir = $FalcorDir

. "$PSScriptRoot\env.ps1"

$FalcorDir = if ($requestedFalcorDir) { $requestedFalcorDir } else { $script:FalcorDir }

$cmakeLists = Join-Path $FalcorDir 'Source\RenderPasses\CMakeLists.txt'
Assert-Path $FalcorDir 'vendor/falcor is missing.'
Assert-Path $cmakeLists 'Unexpected Falcor layout: Source/RenderPasses/CMakeLists.txt not found.'

$relative = 'Source/RenderPasses/CMakeLists.txt'

$dirty = & git -C $FalcorDir status --short -- $relative
if (-not $dirty) {
    Write-Ok "$relative already matches upstream."
    return
}

if ($PSCmdlet.ShouldProcess($cmakeLists, 'restore upstream content')) {
    & git -C $FalcorDir checkout -- $relative
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for $relative" }
    Write-Ok "$relative restored to upstream."
}

$status = & git -C $FalcorDir status --short
if ($status) {
    Write-Warn 'vendor/falcor still has other local changes (expected only if you patched upstream, see patches/README.md):'
    $status | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}
else {
    Write-Ok 'vendor/falcor is completely clean.'
}

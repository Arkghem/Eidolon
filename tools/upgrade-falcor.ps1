#requires -Version 5.1
<#
.SYNOPSIS
    Move the vendored Falcor submodule to another tag/commit, safely.

.DESCRIPTION
    The only local modification inside vendor/falcor is the generated pass
    overlay. A plain `git checkout <ref>` refuses to run with that file dirty, so
    this script enforces the correct order:

        clean overlay -> fetch ref -> checkout -> update submodules
        -> re-inject overlay -> reconfigure -> rebuild

    If the build breaks after the upgrade, roll back with the previous commit:

        pwsh -File tools\upgrade-falcor.ps1 -Ref <old-sha>

.EXAMPLE
    pwsh -File tools\upgrade-falcor.ps1 -Ref 9.0

.EXAMPLE
    pwsh -File tools\upgrade-falcor.ps1 -Ref master -NoBuild
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Ref,
    [switch]$NoBuild
)

. "$PSScriptRoot\env.ps1"

Assert-Path $script:FalcorDir 'vendor\falcor is missing.'
Assert-Path (Join-Path $script:FalcorDir '.git') 'vendor\falcor is not a git checkout.'

$oldSha = & git -C $script:FalcorDir rev-parse --short HEAD
Write-Step "current vendor\falcor: $oldSha"

# 1. Remove the generated overlay so checkout cannot refuse.
& (Join-Path $PSScriptRoot 'clean-passes.ps1')

$otherChanges = & git -C $script:FalcorDir status --short
if ($otherChanges) {
    Write-Fail 'vendor/falcor still has local modifications:'
    $otherChanges | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
    throw 'Refusing to upgrade. Commit them as patches/ (see patches/README.md) or discard them, then re-run.'
}

# 2. Fetch the ref. Respect shallow clones: only ask for what we need.
$isShallow = Test-Path (Join-Path $script:FalcorDir '.git\shallow')
if ($isShallow) {
    Write-Skip 'shallow clone detected; fetching the ref with depth 1'
    Invoke-Native git @('-C', $script:FalcorDir, 'fetch', '--depth', '1', 'origin', "refs/tags/$Ref:refs/tags/$Ref") | Out-Null
}
else {
    Write-Skip 'fetching tags'
    Invoke-Native git @('-C', $script:FalcorDir, 'fetch', '--tags', 'origin') | Out-Null
}

Invoke-Native git @('-C', $script:FalcorDir, 'checkout', $Ref) | Out-Null

# 3. Submodules (Falcor depends on pybind11/glfw/args/fmt/imgui/vulkan-headers).
$subArgs = @('-C', $script:FalcorDir, 'submodule', 'update', '--init', '--recursive')
if ($isShallow) { $subArgs += @('--depth', '1') }
Invoke-Native git $subArgs | Out-Null

$newSha = & git -C $script:FalcorDir rev-parse --short HEAD
Write-Ok "vendor\falcor: $oldSha -> $newSha ($Ref)"

# 4. Re-inject our passes and rebuild.
& (Join-Path $PSScriptRoot 'sync-passes.ps1')
if (-not $NoBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') -Configure
}

Write-Host ''
Write-Step 'Next:'
Write-Host "   git add vendor/falcor && git commit -m 'chore(falcor): upgrade to $Ref'"
Write-Host '   If the build broke, roll back with:'
Write-Host "       pwsh -File tools\upgrade-falcor.ps1 -Ref $oldSha"

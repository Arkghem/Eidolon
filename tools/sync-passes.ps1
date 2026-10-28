#requires -Version 5.1
<#
.SYNOPSIS
    Inject the research render-pass libraries from research/passes.txt into the
    vendored Falcor build tree.

.DESCRIPTION
    Falcor discovers render-pass libraries through add_subdirectory() calls in
    vendor/falcor/Source/RenderPasses/CMakeLists.txt. We never edit that file by
    hand. Instead this script:

      1. restores it to the pristine upstream content (git show HEAD:<path>),
      2. appends one generated, clearly marked block with an add_subdirectory()
         entry per registered package,
      3. writes the result back as UTF-8 without BOM.

    The source paths are absolute (they point outside the Falcor tree), so CMake
    needs an explicit binary directory -- that is the second argument of
    add_subdirectory(). Because the paths are absolute, re-run this script after
    moving the repository.

    Idempotent: running it twice produces byte-identical output.

.EXAMPLE
    pwsh -File tools\sync-passes.ps1

.EXAMPLE
    pwsh -File tools\sync-passes.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Registry,
    [string]$FalcorDir,
    [switch]$Check
)

# Capture the argument before dot-sourcing env.ps1: that file assigns
# $script:FalcorDir, which shares the scope (and therefore the variable) with the
# -FalcorDir parameter and would overwrite it.
$requestedFalcorDir = $FalcorDir

. "$PSScriptRoot\env.ps1"

if (-not $Registry) { $Registry = $script:PassRegistry }
$FalcorDir = if ($requestedFalcorDir) { $requestedFalcorDir } else { $script:FalcorDir }

$passesRoot = Join-Path $script:EidolonRoot 'research\passes'
$cmakeLists = Join-Path $FalcorDir 'Source\RenderPasses\CMakeLists.txt'

Assert-Path $FalcorDir 'vendor/falcor is missing. Run: git submodule update --init --recursive'
Assert-Path (Join-Path $FalcorDir '.git') 'vendor/falcor is not a git checkout.'
Assert-Path $cmakeLists 'Unexpected Falcor layout: Source/RenderPasses/CMakeLists.txt not found.'

# -----------------------------------------------------------------------------
# Read + validate the registry
# -----------------------------------------------------------------------------

if (-not (Test-Path $Registry)) {
    Write-Warn "Registry not found: $Registry - nothing to inject."
    $packages = @()
}
else {
    $packages = @()
    $lineNo = 0
    foreach ($raw in (Get-Content -Path $Registry -Encoding UTF8)) {
        $lineNo++
        $line = $raw.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith('#')) { continue }
        if ($line -match '\s') {
            throw "passes.txt:$lineNo invalid entry '$line' (package names must not contain whitespace)."
        }
        if ($packages -contains $line) {
            throw "passes.txt:$lineNo duplicate entry '$line'."
        }
        $packages += $line
    }
    $packages = $packages | Sort-Object
}

foreach ($pkg in $packages) {
    $dir = Join-Path $passesRoot $pkg
    if (-not (Test-Path $dir)) {
        throw "passes.txt lists '$pkg' but $dir does not exist."
    }
    if (-not (Test-Path (Join-Path $dir 'CMakeLists.txt'))) {
        throw "passes.txt lists '$pkg' but $dir\CMakeLists.txt does not exist."
    }
}

# -----------------------------------------------------------------------------
# Build the generated block
# -----------------------------------------------------------------------------

function ConvertTo-CmakePath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

$lines = New-Object System.Collections.Generic.List[string]

$lines.Add($script:OverlayMarkerBegin)

# The shared helper library must be added first: every pass links EidolonShared.
$sharedDir = Join-Path $script:EidolonRoot 'research\shared'
if (Test-Path (Join-Path $sharedDir 'CMakeLists.txt')) {
    $sharedSrc = ConvertTo-CmakePath $sharedDir
    # ${CMAKE_BINARY_DIR} must reach CMake verbatim -> double quotes + escaped $.
    $sharedBin = "`${CMAKE_BINARY_DIR}/eidolon/shared"
    $lines.Add("add_subdirectory($sharedSrc $sharedBin)")
}

foreach ($pkg in $packages) {
    $srcDir = ConvertTo-CmakePath (Join-Path $passesRoot $pkg)
    $binDir = "`${CMAKE_BINARY_DIR}/eidolon/$pkg"
    $lines.Add("add_subdirectory($srcDir $binDir)")
}
$lines.Add($script:OverlayMarkerEnd)

# -----------------------------------------------------------------------------
# Restore upstream content, then append the block
# -----------------------------------------------------------------------------

$upstream = & git -C $FalcorDir show 'HEAD:Source/RenderPasses/CMakeLists.txt' 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "git show failed for Source/RenderPasses/CMakeLists.txt:`n$($upstream -join "`n")"
}

# Normalize to LF, drop trailing blank lines, keep exactly one final newline.
$base = ($upstream -join "`n") -replace "`r`n", "`n"
$base = $base.TrimEnd("`n")

$content = $base + "`n`n" + (($lines | ForEach-Object { $_ }) -join "`n") + "`n"
$content = $content -replace "`r`n", "`n"

# -----------------------------------------------------------------------------
# Compare / write
# -----------------------------------------------------------------------------

$current = ''
if (Test-Path $cmakeLists) {
    $current = [System.IO.File]::ReadAllText($cmakeLists)
    $current = $current -replace "`r`n", "`n"
}

if ($current -ceq $content) {
    Write-Ok "vendor/falcor injection already up to date ($($packages.Count) package(s))."
    # Explicit exit code: callers (verify.ps1 -Check) inspect $LASTEXITCODE.
    exit 0
}

if ($Check) {
    Write-Fail "vendor/falcor injection is stale - run tools\sync-passes.ps1"
    exit 1
}

if ($PSCmdlet.ShouldProcess($cmakeLists, "write overlay block ($($packages.Count) package(s))")) {
    Write-Utf8NoBom -Path $cmakeLists -Content $content
    Write-Ok "Injected $($packages.Count) package(s): $($packages -join ', ')"
    Write-Step 'Re-run CMake configure so the new subdirectories are picked up: tools\build.ps1 -Configure'
}

$status = & git -C $FalcorDir status --short
Write-Host ''
Write-Host 'vendor/falcor working tree:' -ForegroundColor DarkGray
if ($status) { $status | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
else { Write-Host '  (clean)' -ForegroundColor DarkGray }

exit 0

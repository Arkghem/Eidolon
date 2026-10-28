#requires -Version 5.1
<#
.SYNOPSIS
    Run clang-format over the research code using the formatter that Falcor ships.

.DESCRIPTION
    Falcor pulls clang-format 15 through packman; using the same binary and the
    same style file as upstream keeps our passes visually consistent with the
    framework, which matters when you copy a pattern out of an upstream pass.

    Only our code is formatted. The vendored Falcor tree is never touched.

.EXAMPLE
    pwsh -File tools\format.ps1

.EXAMPLE
    pwsh -File tools\format.ps1 -Check
#>
[CmdletBinding()]
param(
    [switch]$Check
)

. "$PSScriptRoot\env.ps1"

# Locate the packman clang-format. Layout has changed over time, so probe a few
# candidates instead of hard-coding one path.
$candidates = @(
    (Join-Path $script:FalcorDir 'tools\.packman\clang-format\bin\clang-format.exe'),
    (Join-Path $script:FalcorDir 'tools\.packman\clang-format\clang-format.exe'),
    (Join-Path $script:FalcorDir 'external\packman\clang-format\bin\clang-format.exe')
)
$clangFormat = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $clangFormat) {
    $found = Get-ChildItem (Join-Path $script:FalcorDir 'tools\.packman') -Recurse -Filter 'clang-format*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $clangFormat = $found.FullName }
}
if (-not $clangFormat) {
    throw 'clang-format not found under vendor\falcor\tools\.packman. Run tools\build.ps1 once so packman pulls the tools, or install clang-format 15 manually.'
}

# Prefer Falcor's own .clang-format so formatting matches upstream.
$styleFile = Join-Path $script:FalcorDir '.clang-format'
if (-not (Test-Path $styleFile)) {
    Write-Warn "No .clang-format in vendor\falcor; falling back to -style=file (searches upwards from each source file)."
    $styleArg = '-style=file'
}
else {
    $styleArg = "-style=file:$styleFile"
}

$extensions = @('.h', '.hpp', '.cpp', '.slang', '.slangh')
$roots = @(
    (Join-Path $script:EidolonRoot 'research')
)

$targets = @()
foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    $targets += Get-ChildItem $root -Recurse -File | Where-Object { $extensions -contains $_.Extension }
}

if ($targets.Count -eq 0) {
    Write-Warn 'No source files to format.'
    return
}

Write-Step "clang-format ($(if ($Check) { 'check' } else { 'apply' })): $($targets.Count) file(s)"
Write-Skip "binary: $clangFormat"
Write-Skip "style : $styleArg"

$changed = @()
foreach ($file in $targets) {
    if ($Check) {
        & $clangFormat $styleArg --dry-run --Werror $file.FullName 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $changed += $file.FullName }
    }
    else {
        $before = [System.IO.File]::ReadAllText($file.FullName)
        & $clangFormat $styleArg -i $file.FullName
        $after = [System.IO.File]::ReadAllText($file.FullName)
        if ($before -cne $after) { $changed += $file.FullName }
    }
}

if ($Check) {
    if ($changed.Count -gt 0) {
        Write-Fail "files need formatting:"
        $changed | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
        exit 1
    }
    Write-Ok 'all files formatted.'
    return
}

if ($changed.Count -eq 0) { Write-Ok 'no changes needed.' }
else {
    Write-Ok "reformatted $($changed.Count) file(s):"
    $changed | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
}

#requires -Version 5.1
<#
.SYNOPSIS
    Create a new research render-pass library from research/passes/_template.

.DESCRIPTION
    Copies the template, renames every __PASS_NAME__ occurrence (file names and
    file contents), and appends the new package to research/passes.txt.

    The library name becomes: directory name == CMake target == plugin DLL name,
    which is what Falcor's plugin manager uses to find it.

.EXAMPLE
    pwsh -File tools\new-pass.ps1 -Name ReSTIRPT
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name
)

. "$PSScriptRoot\env.ps1"

if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
    throw "Invalid pass name '$Name'. Use letters, digits and underscores, starting with a letter (it becomes a C++ class and DLL name)."
}

$templateDir = Join-Path $script:EidolonRoot 'research\passes\_template'
$targetDir = Join-Path $script:EidolonRoot "research\passes\$Name"

Assert-Path $templateDir 'research\passes\_template is missing.'
if (Test-Path $targetDir) { throw "research\passes\$Name already exists." }

New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

$files = Get-ChildItem $templateDir -Recurse -File
foreach ($file in $files) {
    $relative = $file.FullName.Substring($templateDir.Length).TrimStart('\')
    $newRelative = $relative.Replace('__PASS_NAME__', $Name)
    $destPath = Join-Path $targetDir $newRelative
    $destDir = Split-Path -Parent $destPath
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $content = [System.IO.File]::ReadAllText($file.FullName)
    $content = $content.Replace('__PASS_NAME__', $Name)
    Write-Utf8NoBom -Path $destPath -Content $content
    Write-Host "   + $newRelative" -ForegroundColor DarkGray
}

# Register the package.
$registryText = [System.IO.File]::ReadAllText($script:PassRegistry)
if ($registryText -notmatch "(?m)^\s*$([regex]::Escape($Name))\s*$") {
    $registryText = $registryText.TrimEnd("`r", "`n") + "`n" + $Name + "`n"
    Write-Utf8NoBom -Path $script:PassRegistry -Content $registryText
    Write-Ok "registered '$Name' in research/passes.txt"
}

Write-Host ''
Write-Ok "created research\passes\$Name"
Write-Host '   next steps:'
Write-Host "     1. fill in $Name.h/.cpp and shaders\$Name.cs.slang"
Write-Host '     2. pwsh -File tools\sync-passes.ps1'
Write-Host '     3. pwsh -File tools\build.ps1 -Configure -Target ' -NoNewline
Write-Host $Name

#requires -Version 5.1
<#
.SYNOPSIS
    Create a new experiment directory from experiments/_template.

.DESCRIPTION
    Experiments are numbered directories: NNNN-kebab-slug. The number is derived
    from the highest existing experiment, so ordering in the file explorer (and
    in git history) matches the chronology of the work.

    Placeholders replaced inside the template:
        <NNNN-slug>   -> 0007-my-experiment
        <GRAPH_NAME>  -> MyExperiment (PascalCase, used as the Python symbol)
        <PassName>    -> the -Pass argument (default HelloPass)

.EXAMPLE
    pwsh -File tools\new-experiment.ps1 -Slug restir-energy-compensation
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Slug,
    [string]$Pass = 'HelloPass'
)

. "$PSScriptRoot\env.ps1"

$slugClean = $Slug.Trim().ToLowerInvariant()
if ($slugClean -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
    throw "Invalid slug '$Slug'. Use kebab-case: lowercase letters, digits and single dashes."
}

$templateDir = Join-Path $script:EidolonRoot 'experiments\_template'
$experimentsDir = Join-Path $script:EidolonRoot 'experiments'
Assert-Path $templateDir 'experiments\_template is missing.'

# Next free number.
$maxNum = 0
Get-ChildItem $experimentsDir -Directory | Where-Object { $_.Name -match '^(\d{4})-' } | ForEach-Object {
    $n = [int]$matches[1]
    if ($n -gt $maxNum) { $maxNum = $n }
}
$next = $maxNum + 1
$fullName = '{0:D4}-{1}' -f $next, $slugClean
$targetDir = Join-Path $experimentsDir $fullName

if (Test-Path $targetDir) { throw "$targetDir already exists." }
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

$pascal = (($slugClean -split '-') | ForEach-Object {
    if ($_.Length -gt 0) { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
}) -join ''

$files = Get-ChildItem $templateDir -Recurse -File
foreach ($file in $files) {
    $relative = $file.FullName.Substring($templateDir.Length).TrimStart('\')
    $destPath = Join-Path $targetDir $relative
    $destDir = Split-Path -Parent $destPath
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $content = [System.IO.File]::ReadAllText($file.FullName)
    $content = $content.Replace('<NNNN-slug>', $fullName)
    $content = $content.Replace('<GRAPH_NAME>', $pascal)
    $content = $content.Replace('<PassName>', $Pass)
    Write-Utf8NoBom -Path $destPath -Content $content
    Write-Host "   + $relative" -ForegroundColor DarkGray
}

# Rename the template graph to something meaningful.
$graphTemplate = Join-Path $targetDir 'graphs\graph.py'
if (Test-Path $graphTemplate) {
    $graphName = ($slugClean -replace '-', '_') + '.py'
    Move-Item $graphTemplate (Join-Path $targetDir "graphs\$graphName") -Force
    $cfgPath = Join-Path $targetDir 'configs\default.json'
    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8
    $cfg = $cfg.Replace('graphs/graph.py', "graphs/$graphName")
    Write-Utf8NoBom -Path $cfgPath -Content $cfg
}

Write-Host ''
Write-Ok "created experiments\$fullName"
Write-Host '   next steps:'
Write-Host "     1. edit experiments\$fullName\README.md (question / hypothesis first)"
Write-Host "     2. point configs\default.json at your graph"
Write-Host "     3. pwsh -File tools\run-experiment.ps1 -Experiment $fullName"

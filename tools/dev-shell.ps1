#requires -Version 5.1
<#
.SYNOPSIS
    Enter a Visual Studio developer shell (MSVC/cl on PATH) for this workspace.

.DESCRIPTION
    Only needed for the `windows-ninja-msvc` preset; the default
    `windows-vs2022` preset finds MSVC by itself. MinGW's gcc cannot build Falcor.

    A child process cannot change its parent's environment, so:

      * dot-source it to stay in your shell:   . .\tools\dev-shell.ps1
      * or run it with -NoExit:                pwsh -NoExit -File tools\dev-shell.ps1
      * or let it drive a build:               pwsh -File tools\dev-shell.ps1 -Build

.EXAMPLE
    . .\tools\dev-shell.ps1
    cmake --preset windows-ninja-msvc
#>
[CmdletBinding()]
param(
    [switch]$Build,
    [ValidateSet('x64', 'x86', 'arm64')][string]$Arch = 'x64'
)

. "$PSScriptRoot\env.ps1"

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw 'vswhere.exe not found: Visual Studio 2022 Build Tools is not installed. See docs/00-environment.md.'
}

$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($vsPath)) {
    throw 'No Visual Studio installation with the C++ (VCTools) workload. Add "Desktop development with C++".'
}
$vsPath = $vsPath.Trim()

$launchDevShell = Join-Path $vsPath 'Common7\Tools\Launch-VsDevShell.ps1'
if (-not (Test-Path $launchDevShell)) {
    throw "Launch-VsDevShell.ps1 not found under $vsPath"
}

$hostArch = if ($Arch -eq 'x86') { 'x86' } else { 'x64' }
& $launchDevShell -VsInstallationPath $vsPath -Arch "amd64" -HostArch "amd64" -SkipAutomaticLocation

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Write-Warn 'cl.exe still not on PATH - the dev shell may not have initialized correctly.'
}
else {
    Write-Ok "MSVC ready (cl: $((Get-Command cl).Source))"
    Write-Skip "VS: $vsPath"
}

if ($Build) {
    & (Join-Path $PSScriptRoot 'build.ps1')
}

#requires -Version 5.1
<#
.SYNOPSIS
    P0: install the Windows build toolchain required by Falcor plus RenderDoc.

.DESCRIPTION
    Idempotent. Detects which pieces are present and installs only what is missing:

      * Visual Studio 2022 Build Tools  (MSVC v143 + MSBuild)
      * Windows SDK 10.0.19041           (Falcor's CMake preset pins CMAKE_SYSTEM_VERSION)
      * RenderDoc 1.46+                  (frame capture)

    The installers need administrator rights. When the calling shell is not
    elevated the script relaunches itself through UAC and returns immediately;
    progress is logged to out\logs\p0-install.log.

.EXAMPLE
    pwsh -File tools\install-toolchain.ps1

.EXAMPLE
    powershell -File tools\install-toolchain.ps1 -SkipRenderDoc
#>
[CmdletBinding()]
param(
    [switch]$SkipVisualStudio,
    [switch]$SkipRenderDoc,
    # Internal: set when the script relaunched itself elevated.
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $RepoRoot 'out\logs'
$LogPath = Join-Path $LogDir 'p0-install.log'

$VsPackageId = 'Microsoft.VisualStudio.2022.BuildTools'
$RenderDocPackageId = 'BaldurKarlsson.RenderDoc'
$RequiredSdkVersion = '10.0.19041.0'
$VsWorkloadArgs = @(
    '--quiet'
    '--wait'
    '--norestart'
    '--nocache'
    '--add', 'Microsoft.VisualStudio.Workload.VCTools'
    '--add', 'Microsoft.VisualStudio.Component.Windows10SDK.19041'
    '--includeRecommended'
)

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Step {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] == $Message"
    Write-Host $line -ForegroundColor Cyan
    if (Test-Path (Split-Path -Parent $LogPath)) { Add-Content -Path $LogPath -Value $line }
}

function Write-Note {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')]    $Message"
    Write-Host $line
    if (Test-Path (Split-Path -Parent $LogPath)) { Add-Content -Path $LogPath -Value $line }
}

function Resolve-Winget {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $fallback) { return $fallback }
    throw 'winget.exe not found. Install "App Installer" from the Microsoft Store, or install the toolchain manually (see docs/00-environment.md).'
}

function Invoke-Winget {
    param([string[]]$Arguments)
    $winget = Resolve-Winget
    Write-Note "winget $($Arguments -join ' ')"
    & $winget @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "winget failed with exit code $code. Args: $($Arguments -join ' ')"
    }
}

function Get-VsInstallPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($path)) { return $null }
    return $path.Trim()
}

function Test-Sdk19041 {
    return Test-Path 'C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0'
}

function Get-RenderDocExe {
    $candidates = @(
        'C:\Program Files\RenderDoc\qrenderdoc.exe'
        'C:\Program Files\RenderDoc\renderdoccmd.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command qrenderdoc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# -----------------------------------------------------------------------------
# Elevation
# -----------------------------------------------------------------------------

if (-not (Test-Elevated) -and -not $Elevated) {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    if (Test-Path $LogPath) { Remove-Item $LogPath -Force }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    if ($SkipVisualStudio) { $argList += '-SkipVisualStudio' }
    if ($SkipRenderDoc) { $argList += '-SkipRenderDoc' }

    Write-Host 'Administrator rights are required to install Visual Studio Build Tools / RenderDoc.' -ForegroundColor Yellow
    Write-Host 'Requesting elevation through UAC. Accept the prompt to continue.' -ForegroundColor Yellow
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    Write-Host "Elevated installer launched. Watch progress with:" -ForegroundColor Green
    Write-Host "    Get-Content '$LogPath' -Wait" -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
Write-Step "Eidolon P0 toolchain install (elevated=$([bool](Test-Elevated)))"

# -----------------------------------------------------------------------------
# Visual Studio 2022 Build Tools + Windows SDK 10.0.19041
# -----------------------------------------------------------------------------

if (-not $SkipVisualStudio) {
    $vsPath = Get-VsInstallPath
    $sdkOk = Test-Sdk19041

    if ($vsPath -and $sdkOk) {
        Write-Note "Visual Studio with C++ tools already present: $vsPath"
        Write-Note "Windows SDK $RequiredSdkVersion already present."
    }
    elseif ($vsPath -and -not $sdkOk) {
        # MSVC is there, only the pinned SDK is missing. Modify the existing install.
        Write-Step "Windows SDK $RequiredSdkVersion missing - adding it to the existing VS install"
        $modifyArgs = @(
            'modify'
            '--id', $VsPackageId
            '-e'
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--disable-interactivity'
            '--override', ('"' + ($VsWorkloadArgs -join ' ') + ' --add Microsoft.VisualStudio.Component.Windows10SDK.19041"')
        )
        Invoke-Winget -Arguments $modifyArgs
    }
    else {
        Write-Step "Installing $VsPackageId (VCTools workload + Windows SDK $RequiredSdkVersion)"
        Write-Note 'This downloads several GB and usually takes 10-40 minutes.'
        $installArgs = @(
            'install'
            '--id', $VsPackageId
            '-e'
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--disable-interactivity'
            '--override', ('"' + ($VsWorkloadArgs -join ' ') + '"')
        )
        Invoke-Winget -Arguments $installArgs
    }

    $vsPath = Get-VsInstallPath
    if (-not $vsPath) {
        Write-Note 'WARNING: vswhere still cannot find MSVC after the install. Check the VS installer log, a reboot may be required.'
    }
    else {
        Write-Note "MSVC found at: $vsPath"
    }
    if (-not (Test-Sdk19041)) {
        Write-Note "WARNING: Windows SDK $RequiredSdkVersion still missing. Falcor's preset pins it; either install component 'Microsoft.VisualStudio.Component.Windows10SDK.19041' or configure with -DCMAKE_SYSTEM_VERSION=<installed version>."
    }
    else {
        Write-Note "Windows SDK $RequiredSdkVersion OK"
    }
}
else {
    Write-Note 'Skipping Visual Studio (requested).'
}

# -----------------------------------------------------------------------------
# RenderDoc
# -----------------------------------------------------------------------------

if (-not $SkipRenderDoc) {
    $rdoc = Get-RenderDocExe
    if ($rdoc) {
        Write-Note "RenderDoc already present: $rdoc"
    }
    else {
        Write-Step "Installing $RenderDocPackageId"
        Invoke-Winget -Arguments @(
            'install'
            '--id', $RenderDocPackageId
            '-e'
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--disable-interactivity'
        )
        $rdoc = Get-RenderDocExe
        if ($rdoc) { Write-Note "RenderDoc installed: $rdoc" }
        else { Write-Note 'WARNING: RenderDoc not found after install; re-run tools/verify.ps1 to diagnose.' }
    }
}
else {
    Write-Note 'Skipping RenderDoc (requested).'
}

Write-Step 'P0 toolchain install finished. Next: tools\verify.ps1'

# -----------------------------------------------------------------------------
# Post-install summary
# -----------------------------------------------------------------------------

$vsPath = Get-VsInstallPath
Write-Note ('VS2022 C++ tools : ' + $(if ($vsPath) { $vsPath } else { 'MISSING' }))
Write-Note ('Windows SDK 19041: ' + $(if (Test-Sdk19041) { 'OK' } else { 'MISSING' }))
Write-Note ('RenderDoc        : ' + $(if (Get-RenderDocExe) { Get-RenderDocExe } else { 'MISSING' }))

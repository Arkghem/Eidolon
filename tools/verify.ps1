#requires -Version 5.1
<#
.SYNOPSIS
    Check that this machine can build and run the Eidolon/Falcor workspace.

.DESCRIPTION
    Read-only health check. Groups problems into:

      HARD  - build cannot succeed without fixing it (exit code 1)
      SOFT  - workflow degraded, but you can still build (exit code 0 with warnings)

    Run it after tools/install-toolchain.ps1, and again whenever something
    suddenly stops working.

.EXAMPLE
    pwsh -File tools\verify.ps1
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

. "$PSScriptRoot\env.ps1"

$hard = New-Object System.Collections.Generic.List[string]
$soft = New-Object System.Collections.Generic.List[string]

function Report {
    param([string]$Status, [string]$Name, [string]$Detail)
    $color = switch ($Status) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("  [{0,-4}] {1,-22} {2}" -f $Status, $Name, $Detail) -ForegroundColor $color
}

Write-Host ''
Write-Host 'Eidolon environment check' -ForegroundColor Cyan
Write-Host ('  repo: ' + $script:EidolonRoot)
Write-Host ''

# -----------------------------------------------------------------------------
# 1. Visual Studio 2022 + MSVC
# -----------------------------------------------------------------------------

$vsPath = $null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    Report 'FAIL' 'Visual Studio 2022' 'vswhere.exe not found -> run tools\install-toolchain.ps1'
    $hard.Add('Visual Studio 2022 Build Tools (MSVC v143) is not installed.')
}
else {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ([string]::IsNullOrWhiteSpace($vsPath)) {
        Report 'FAIL' 'Visual Studio 2022' 'no install with the C++ workload (VCTools)'
        $hard.Add('Visual Studio 2022 is installed but missing the "Desktop development with C++" workload (VCTools).')
    }
    else {
        $vsVersion = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion 2>$null
        Report 'OK' 'Visual Studio 2022' ("{0} ({1})" -f $vsVersion.Trim(), $vsPath.Trim())
        $msvcRoot = Join-Path $vsPath.Trim() 'VC\Tools\MSVC'
        if (Test-Path $msvcRoot) {
            $toolset = Get-ChildItem $msvcRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
            if ($toolset) { Report 'OK' 'MSVC toolset' $toolset.Name }
        }
    }
}

# -----------------------------------------------------------------------------
# 2. Windows SDK 10.0.19041 (Falcor's preset pins CMAKE_SYSTEM_VERSION)
# -----------------------------------------------------------------------------

$sdkRoot = 'C:\Program Files (x86)\Windows Kits\10\Include'
$requiredSdk = '10.0.19041.0'
if (-not (Test-Path $sdkRoot)) {
    Report 'FAIL' 'Windows SDK' 'no Windows Kits\10\Include directory'
    $hard.Add('Windows SDK is not installed.')
}
else {
    $sdks = Get-ChildItem $sdkRoot -Directory | Select-Object -ExpandProperty Name
    if (Test-Path (Join-Path $sdkRoot $requiredSdk)) {
        Report 'OK' 'Windows SDK 19041' $requiredSdk
    }
    else {
        Report 'FAIL' 'Windows SDK 19041' ("missing; installed: " + ($sdks -join ', '))
        $hard.Add("Windows SDK $requiredSdk is missing (Falcor's windows-vs2022 preset pins it). Install component 'Microsoft.VisualStudio.Component.Windows10SDK.19041', or configure with -DCMAKE_SYSTEM_VERSION=<installed>.")
    }
}

# -----------------------------------------------------------------------------
# 3. GPU + driver
# -----------------------------------------------------------------------------

$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if (-not $smi) {
    $alt = 'C:\Windows\System32\nvidia-smi.exe'
    if (Test-Path $alt) { $smi = [pscustomobject]@{ Source = $alt } }
}
if (-not $smi) {
    Report 'FAIL' 'NVIDIA GPU' 'nvidia-smi not found (DXR-capable GPU + driver 535+ required)'
    $hard.Add('nvidia-smi not found. Falcor needs an RTX-class DXR GPU with driver >= 535.')
}
else {
    $csv = & $smi.Source --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $csv) {
        Report 'FAIL' 'NVIDIA GPU' 'nvidia-smi failed'
        $hard.Add('nvidia-smi could not query the GPU.')
    }
    else {
        $parts = ($csv | Select-Object -First 1) -split ',\s*'
        $gpuName = $parts[0]
        $driver = $parts[1]
        $vram = $parts[2]
        $driverOk = $false
        try { $driverOk = ([version]$driver -ge [version]'535.0') } catch { $driverOk = $false }
        if ($driverOk) { Report 'OK' 'NVIDIA GPU' "$gpuName / driver $driver / $vram" }
        else {
            Report 'FAIL' 'NVIDIA GPU' "$gpuName / driver $driver (needs >= 535)"
            $hard.Add("NVIDIA driver $driver is too old; Falcor requires >= 535.")
        }
        if ($vram -match '(\d+)') {
            $vramMiB = [int]$matches[1]
            if ($vramMiB -lt 10000) {
                Report 'WARN' 'VRAM' "$vramMiB MiB - keep experiments at 1080p, low spp, avoid RTXDI+NRD together"
                $soft.Add("Only $vramMiB MiB VRAM: default experiments to 1080p and few samples.")
            }
        }
    }
}

# -----------------------------------------------------------------------------
# 4. Disk space (build tree + packman land on the repo drive)
# -----------------------------------------------------------------------------

$drive = (Get-Item $script:EidolonRoot).PSDrive
if ($drive) {
    $freeGb = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGb -ge 60) { Report 'OK' 'disk free' ("{0}: {1} GB" -f $drive.Name, $freeGb) }
    else {
        Report 'WARN' 'disk free' ("{0}: {1} GB (recommend >= 60 GB)" -f $drive.Name, $freeGb)
        $soft.Add("Only $freeGb GB free on $($drive.Name):. A Falcor build plus packman deps needs roughly 25-40 GB.")
    }
}

# -----------------------------------------------------------------------------
# 5. git + submodule + packman state
# -----------------------------------------------------------------------------

if (Get-Command git -ErrorAction SilentlyContinue) { Report 'OK' 'git' ((& git --version)) }
else { Report 'FAIL' 'git' 'not found'; $hard.Add('git is not installed.') }

$lfs = Get-Command git-lfs -ErrorAction SilentlyContinue
if ($lfs) { Report 'OK' 'git-lfs' (& git lfs version) } else { Report 'WARN' 'git-lfs' 'not found (not required yet)' }

if (Test-Path (Join-Path $script:FalcorDir '.git')) {
    $tag = & git -C $script:FalcorDir describe --tags --always 2>$null
    Report 'OK' 'vendor/falcor' ("checked out at $tag")
    $cmakeLists = Join-Path $script:FalcorDir 'Source\RenderPasses\CMakeLists.txt'
    if (Test-Path $cmakeLists) {
        $status = & git -C $script:FalcorDir status --short
        if (-not $status) { Report 'OK' 'falcor worktree' 'clean' }
        else {
            $other = $status | Where-Object { $_ -notmatch 'Source/RenderPasses/CMakeLists.txt' }
            if ($other) {
                Report 'WARN' 'falcor worktree' 'modified files besides the overlay (see patches/README.md)'
                $soft.Add('vendor/falcor has local modifications other than the pass overlay.')
            }
            else { Report 'OK' 'falcor worktree' 'only the eidolon overlay (expected)' }
        }
        $syncScript = Join-Path $PSScriptRoot 'sync-passes.ps1'
        & $syncScript -Check *> $null
        if ($LASTEXITCODE -eq 0) { Report 'OK' 'pass overlay' 'up to date with research/passes.txt' }
        else {
            Report 'WARN' 'pass overlay' 'stale -> run tools\sync-passes.ps1'
            $soft.Add('The generated pass overlay is stale; run tools\sync-passes.ps1 and reconfigure.')
        }
    }
    $packmanDir = Join-Path $script:FalcorDir 'tools\.packman'
    if (Test-Path $packmanDir) { Report 'OK' 'packman deps' 'present' }
    else {
        Report 'WARN' 'packman deps' 'not pulled yet -> tools\build.ps1 runs setup.bat'
        $soft.Add('Packman dependencies are not fetched yet (first build will download them).')
    }
    $pybind = Join-Path $script:FalcorDir 'external\pybind11\CMakeLists.txt'
    if (Test-Path $pybind) { Report 'OK' 'submodules' 'initialized' }
    else {
        Report 'WARN' 'submodules' 'not initialized'
        $soft.Add('Falcor submodules are not initialized: git -C vendor/falcor submodule update --init --recursive')
    }
}
else {
    Report 'FAIL' 'vendor/falcor' 'submodule missing'
    $hard.Add('vendor/falcor is missing. Run: git submodule update --init --recursive')
}

# -----------------------------------------------------------------------------
# 6. RenderDoc
# -----------------------------------------------------------------------------

$rdoc = Get-Command qrenderdoc -ErrorAction SilentlyContinue
$rdocPath = if ($rdoc) { $rdoc.Source } elseif (Test-Path 'C:\Program Files\RenderDoc\qrenderdoc.exe') { 'C:\Program Files\RenderDoc\qrenderdoc.exe' } else { $null }
$rdocCmd = if (Test-Path 'C:\Program Files\RenderDoc\renderdoccmd.exe') { 'C:\Program Files\RenderDoc\renderdoccmd.exe' } else { $null }

if ($rdocPath) {
    $ver = (Get-Item $rdocPath).VersionInfo.FileVersion
    Report 'OK' 'RenderDoc' "$rdocPath ($ver)"
    if ($rdocCmd) { Report 'OK' 'renderdoccmd' $rdocCmd }
    else { Report 'WARN' 'renderdoccmd' 'not found (automated capture unavailable)'; $soft.Add('renderdoccmd.exe missing; only interactive captures work.') }
}
else {
    Report 'WARN' 'RenderDoc' 'not installed -> tools\install-toolchain.ps1'
    $soft.Add('RenderDoc is not installed: frame capture is unavailable.')
}

# -----------------------------------------------------------------------------
# 7. Build tree
# -----------------------------------------------------------------------------

$mogwai = Get-MogwaiExe
if (Test-Path $mogwai) { Report 'OK' 'Mogwai.exe' $mogwai }
else { Report 'WARN' 'Mogwai.exe' 'not built yet -> tools\build.ps1 -Configure'; $soft.Add('Mogwai is not built yet.') }

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

Write-Host ''
if ($hard.Count -eq 0) {
    Write-Ok 'No blocking problems.'
}
else {
    Write-Fail ("{0} blocking problem(s):" -f $hard.Count)
    $hard | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
}
if ($soft.Count -gt 0) {
    Write-Warn ("{0} warning(s):" -f $soft.Count)
    $soft | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
}
Write-Host ''

if ($hard.Count -gt 0) { exit 1 }
exit 0

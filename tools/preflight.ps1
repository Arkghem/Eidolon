#requires -Version 5.1
<#
.SYNOPSIS
    Measure whether this machine's network can actually complete the first-time setup.

.DESCRIPTION
    The first build needs three big downloads:

        Visual Studio 2022 Build Tools     ~8 GB   (Microsoft CDN, via aka.ms)
        Falcor source + submodules         ~70 MB  (codeload.github.com)
        packman dependencies               ~2-4 GB  (NVIDIA CloudFront)

    On a throttled link this is not "slow", it is "impossible to finish today".
    This script spends at most ~30 s measuring real throughput and extrapolating,
    so you decide before burning hours instead of after.

    It never downloads anything to the repo: partial responses go to out\ and are
    deleted immediately.

.EXAMPLE
    pwsh -File tools\preflight.ps1

.EXAMPLE
    pwsh -File tools\preflight.ps1 -Strict      # exit 1 if the toolchain ETA is absurd
#>
[CmdletBinding()]
param(
    [int]$SecondsPerProbe = 12,
    [double]$MaxToolchainHours = 24.0,
    [switch]$Strict
)

. "$PSScriptRoot\env.ps1"

$probeDir = Join-Path $script:EidolonRoot 'out'
if (-not (Test-Path $probeDir)) { New-Item -ItemType Directory -Path $probeDir -Force | Out-Null }
$probeFile = Join-Path $probeDir '_preflight-probe.bin'

function Measure-Throughput {
    param(
        [string]$Label,
        [string]$Url
    )

    if (Test-Path $probeFile) { Remove-Item $probeFile -Force -ErrorAction SilentlyContinue }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $httpCode = ''
    try {
        # stderr must be dropped: curl reports timeouts/progress there, and
        # PowerShell would otherwise turn it into the captured "output".
        $raw = & curl.exe -sS -L --no-progress-meter --max-time $SecondsPerProbe -o $probeFile -w '%{http_code}' $Url 2>$null
        $httpCode = ($raw | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($httpCode)) { $httpCode = '000' }
        elseif ($httpCode -notmatch '^\d{3}$') { $httpCode = ($httpCode -split "`n" | Where-Object { $_ -match '^\d{3}$' } | Select-Object -Last 1) }
        if ([string]::IsNullOrWhiteSpace($httpCode)) { $httpCode = '000' }
    }
    catch {
        $httpCode = 'curl-error'
    }
    $sw.Stop()

    $bytes = 0
    if (Test-Path $probeFile) {
        $bytes = (Get-Item $probeFile).Length
        Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
    }

    $seconds = [math]::Max(0.5, $sw.Elapsed.TotalSeconds)
    $kbps = ($bytes / 1KB) / $seconds

    [pscustomobject]@{
        Label    = $Label
        Url      = $Url
        HttpCode = $httpCode
        Bytes    = $bytes
        Seconds  = [math]::Round($seconds, 1)
        Kbps     = [math]::Round($kbps, 1)
        Ok       = ($bytes -gt 0)
    }
}

function Format-Eta {
    param([double]$Kilobytes, [double]$Kbps)
    if ($Kbps -le 0) { return 'never' }
    $totalSeconds = ($Kilobytes / $Kbps)
    if ($totalSeconds -lt 90) { return ('{0:N0}s' -f $totalSeconds) }
    if ($totalSeconds -lt 5400) { return ('{0:N1} min' -f ($totalSeconds / 60)) }
    if ($totalSeconds -lt 172800) { return ('{0:N1} h' -f ($totalSeconds / 3600)) }
    return ('{0:N1} days' -f ($totalSeconds / 86400))
}

Write-Host ''
Write-Host 'Eidolon network preflight' -ForegroundColor Cyan
Write-Host ("  probing for {0}s per target" -f $SecondsPerProbe)
Write-Host ''

$probes = @(
    (Measure-Throughput -Label 'MS CDN (VS bootstrapper)' -Url 'https://aka.ms/vs/17/release/vs_buildtools.exe'),
    (Measure-Throughput -Label 'GitHub (Falcor tarball)' -Url 'https://codeload.github.com/NVIDIAGameWorks/Falcor/tar.gz/refs/tags/9.0')
)

# packman lives on CloudFront; a HEAD to the root returns 403 quickly when the
# host is reachable, which is all we can measure without pulling a real package.
$packmanReachable = $false
$packmanMs = 0
$swPack = [System.Diagnostics.Stopwatch]::StartNew()
try {
    & curl.exe -sS -I --max-time 15 -o NUL 'https://d4i3qtqj3r0z5.cloudfront.net/' 2>&1 | Out-Null
    $packmanMs = [int]$swPack.Elapsed.TotalMilliseconds
    $packmanReachable = ($packmanMs -lt 14000)
}
catch { }

Write-Host ''
Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
$toolchainKbps = 0
foreach ($p in $probes) {
    $rate = if ($p.Seconds -gt 0) { $p.Bytes / 1KB / $p.Seconds } else { 0 }
    if ($p.Label -like 'MS CDN*') { $toolchainKbps = $rate }
    $status = if ($p.Ok) { '[OK  ]' } else { '[FAIL]' }
    $color = if ($p.Ok) { 'Green' } else { 'Red' }
    Write-Host ("  {0} {1,-30} http={2,-4} {3,8} KB in {4,4}s = {5,7:N1} KB/s" -f $status, $p.Label, $p.HttpCode, [math]::Round($p.Bytes / 1KB, 0), $p.Seconds, $rate) -ForegroundColor $color
}
$packStatus = if ($packmanReachable) { '[OK  ]' } else { '[FAIL]' }
$packColor = if ($packmanReachable) { 'Green' } else { 'Red' }
Write-Host ("  {0} {1,-30} host responded in {2} ms (throughput only measurable once packman runs)" -f $packStatus, 'packman (CloudFront)', $packmanMs) -ForegroundColor $packColor
Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray

# Extrapolate. Sizes are order-of-magnitude, good enough for a go/no-go call.
$vsGb = 8.0
$falcorMb = 70.0
$packmanGb = 3.0

$vsEta = Format-Eta -Kilobytes ($vsGb * 1024 * 1024) -Kbps $toolchainKbps
$falcorEta = Format-Eta -Kilobytes ($falcorMb * 1024) -Kbps ($probes[1].Bytes / 1KB / [math]::Max(0.5, $probes[1].Seconds))
$packmanEta = Format-Eta -Kilobytes ($packmanGb * 1024 * 1024) -Kbps $toolchainKbps

Write-Host ''
Write-Host '  extrapolated first-time setup:' -ForegroundColor DarkGray
Write-Host '  (MS CDN rate is measured on the ~4 MB bootstrapper and used as a proxy for the' -ForegroundColor DarkGray
Write-Host '   full ~8 GB layout; treat the number as an order of magnitude, not a promise)' -ForegroundColor DarkGray
Write-Host ("    Visual Studio Build Tools (~{0:N0} GB) : {1}" -f $vsGb, $vsEta)
Write-Host ("    Falcor source (~{0:N0} MB)            : {1}" -f $falcorMb, $falcorEta)
Write-Host ("    packman deps (~{0:N0} GB)             : {1}" -f $packmanGb, $packmanEta)
Write-Host ''

# Verdict.
$vsHours = if ($toolchainKbps -gt 0) { ($vsGb * 1024 * 1024) / $toolchainKbps / 3600 } else { [double]::PositiveInfinity }
$blockers = 0

if (-not $probes[0].Ok) {
    Write-Fail ("Microsoft CDN delivered no data (http={0}, often a stalled redirect). Visual Studio cannot be installed from this machine right now." -f $probes[0].HttpCode)
    $blockers++
}
elseif ($vsHours -gt $MaxToolchainHours) {
    Write-Fail ("Visual Studio download would take ~{0} (> {1} h limit). Use a proxy/VPN, a company mirror, or an offline installer layout." -f $vsEta, $MaxToolchainHours)
    $blockers++
}

if (-not $probes[1].Ok) {
    Write-Fail ("GitHub (codeload) delivered no data (http={0}): Falcor source cannot be fetched." -f $probes[1].HttpCode)
    $blockers++
}

if (-not $packmanReachable) {
    Write-Fail 'packman CloudFront unreachable: dependencies cannot be pulled.'
    $blockers++
}

if ($blockers -eq 0) {
    Write-Ok 'All three sources respond. First-time setup is practical on this link.'
    exit 0
}

Write-Warn ("{0} of 3 sources is/are not usable right now. See docs/00-environment.md section 4." -f $blockers)
if ($Strict) { exit 1 }
exit 0

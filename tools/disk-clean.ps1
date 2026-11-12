# RT Kit - Disk Cleaner (run as admin; output goes to the RT Kit log)
param(
    [switch]$UserTemp,
    [switch]$WinTemp,
    [switch]$RecycleBin,
    [switch]$UpdateCache,
    [switch]$DeliveryOpt,
    [switch]$Thumbnails,
    [switch]$BrowserCache,
    [switch]$ComponentStore
)

function Say([string]$m) { [Console]::Out.WriteLine($m) }
function Get-FreeGB { [math]::Round(([System.IO.DriveInfo]'C:\').AvailableFreeSpace / 1GB, 2) }

function Clear-Folder([string]$Path, [string]$Label) {
    $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue
    if (-not $items) { return }
    $size = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if (-not $size) { $size = 0 }
    $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Say ("  {0,-45} ~{1} MB" -f $Label, [math]::Round($size / 1MB))
}

$skip = @('Public','Default','Default User','All Users','defaultuser0','WDAGUtilityAccount')
$users = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | Where-Object { $skip -notcontains $_.Name }

$before = Get-FreeGB
Say "Free space on C: before: $before GB"
Say ""

if ($UserTemp) {
    Say "[User temp files]"
    foreach ($u in $users) { Clear-Folder "$($u.FullName)\AppData\Local\Temp" "$($u.Name) temp" }
}

if ($WinTemp) {
    Say "[Windows temp files]"
    Clear-Folder 'C:\Windows\Temp' 'C:\Windows\Temp'
}

if ($BrowserCache) {
    Say "[Browser caches]"
    foreach ($u in $users) {
        foreach ($b in @('Google\Chrome', 'Microsoft\Edge', 'BraveSoftware\Brave-Browser')) {
            $ud = "$($u.FullName)\AppData\Local\$b\User Data"
            if (-not (Test-Path $ud)) { continue }
            foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) {
                Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $p = Join-Path $_.FullName $c
                    if (Test-Path $p) { Clear-Folder $p "$($u.Name) $b $($_.Name) $c" }
                }
            }
        }
        $ff = "$($u.FullName)\AppData\Local\Mozilla\Firefox\Profiles"
        if (Test-Path $ff) {
            Get-ChildItem $ff -Directory | ForEach-Object {
                if (Test-Path "$($_.FullName)\cache2") { Clear-Folder "$($_.FullName)\cache2" "$($u.Name) Firefox cache" }
            }
        }
    }
}

if ($Thumbnails) {
    Say "[Thumbnail cache]"
    foreach ($u in $users) {
        $tc = "$($u.FullName)\AppData\Local\Microsoft\Windows\Explorer"
        Get-ChildItem $tc -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Say "  Done (files in use are skipped)"
}

if ($RecycleBin) {
    Say "[Recycle Bin - all users, all drives]"
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady -and $d.DriveType -eq 'Fixed') {
            $rb = Join-Path $d.Name '$Recycle.Bin'
            Get-ChildItem $rb -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Clear-Folder $_.FullName "Recycle Bin $($d.Name) $($_.Name.Substring(0, [math]::Min(14, $_.Name.Length)))"
            }
        }
    }
}

if ($UpdateCache) {
    Say "[Windows Update download cache]"
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    Clear-Folder 'C:\Windows\SoftwareDistribution\Download' 'SoftwareDistribution\Download'
    Start-Service bits, wuauserv -ErrorAction SilentlyContinue
}

if ($DeliveryOpt) {
    Say "[Delivery Optimization cache]"
    try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Say "  Cleared" } catch { Say "  Skipped: $($_.Exception.Message)" }
}

if ($ComponentStore) {
    Say "[Component store cleanup - DISM, can take 5-20 minutes]"
    & dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart | ForEach-Object { if ($_ -match '\S') { Say "  $_" } }
}

$after = Get-FreeGB
Say ""
Say "Free space on C: after : $after GB"
Say ("##FREED {0} GB" -f [math]::Round($after - $before, 2))

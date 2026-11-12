# ==========================================================
#  BackupAgent - nightly cloud backup (runs as SYSTEM)
#  Installed to C:\BackupAgent by install-agent.ps1
#  Uses rclone: sync + versioned archive of changed/deleted files
# ==========================================================
$ErrorActionPreference = 'Continue'

$AgentDir = 'C:\BackupAgent'
$Rclone   = Join-Path $AgentDir 'rclone.exe'
$Config   = Join-Path $AgentDir 'rclone.conf'
$LogDir   = Join-Path $AgentDir 'logs'
$Settings = Get-Content (Join-Path $AgentDir 'settings.json') -Raw | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$Log   = Join-Path $LogDir "backup_$Stamp.log"

function Write-Log([string]$Msg) {
    Add-Content -Path $Log -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg)
}

function Send-Ping([string]$Suffix) {
    if ($Settings.HealthcheckUrl) {
        try { Invoke-WebRequest -Uri ($Settings.HealthcheckUrl + $Suffix) -UseBasicParsing -TimeoutSec 15 | Out-Null } catch { }
    }
}

# Only one copy at a time
$LockFile = Join-Path $AgentDir 'running.lock'
if (Test-Path $LockFile) {
    $age = (Get-Date) - (Get-Item $LockFile).LastWriteTime
    if ($age.TotalHours -lt 12) { Write-Log 'Another backup is still running. Exiting.'; exit 0 }
}
Set-Content -Path $LockFile -Value $PID

$Computer = $env:COMPUTERNAME
$Base     = "$($Settings.Remote):$($Settings.ClientName)/$Computer"
$Failures = 0
$Jobs     = 0

Send-Ping '/start'
Write-Log "Backup started. Client=$($Settings.ClientName) PC=$Computer Dest=$Base"

function Invoke-Sync([string]$Source, [string]$DestPath) {
    $script:Jobs++
    $dest    = "$Base/current/$DestPath"
    $archive = "$Base/archive/$Stamp/$DestPath"
    Write-Log "SYNC  $Source  ->  $dest"
    $rcArgs = @(
        'sync', $Source, $dest,
        '--backup-dir', $archive,
        '--config', $Config,
        '--log-file', $Log, '--log-level', 'NOTICE',
        '--transfers', '4', '--checkers', '8',
        '--retries', '3', '--low-level-retries', '10',
        '--exclude', 'desktop.ini',
        '--exclude', 'Thumbs.db',
        '--exclude', '*.tmp',
        '--exclude', '~$*',
        '--exclude', '*.lnk'
    )
    & $Rclone @rcArgs
    if ($LASTEXITCODE -ne 0) {
        $script:Failures++
        Write-Log "ERROR  rclone exit code $LASTEXITCODE for $Source"
    } else {
        Write-Log "OK    $Source"
    }
}

# ---- User folders ----
$Skip = @('Public','Default','Default User','All Users','defaultuser0','WDAGUtilityAccount')
$Users = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
         Where-Object { $Skip -notcontains $_.Name }

foreach ($u in $Users) {
    foreach ($f in $Settings.Folders) {
        $src = Join-Path $u.FullName $f
        if (Test-Path $src) { Invoke-Sync $src "$($u.Name)/$f" }
    }
}

# ---- Extra paths (e.g. C:\ClientData) ----
foreach ($p in $Settings.ExtraPaths) {
    if ($p -and (Test-Path $p)) {
        $name = ($p -replace '[:\\/ ]+', '_').Trim('_')
        Invoke-Sync $p "_extra/$name"
    } elseif ($p) {
        Write-Log "WARN  Extra path not found: $p"
    }
}

# ---- Remove old versions from the archive ----
$Days = [int]$Settings.KeepVersionsDays
if ($Days -gt 0) {
    Write-Log "Cleaning archive versions older than $Days days"
    & $Rclone delete "$Base/archive" --min-age "${Days}d" --config $Config --log-file $Log --log-level NOTICE
    & $Rclone rmdirs "$Base/archive" --leave-root --config $Config --log-file $Log --log-level NOTICE
}

# ---- Clean old local logs ----
Get-ChildItem $LogDir -Filter 'backup_*.log' |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ---- Result ----
if ($Jobs -eq 0) {
    $Result = 'FAILED - nothing found to back up'
    $Failures = 1
} elseif ($Failures -eq 0) {
    $Result = "OK - $Jobs folder(s) backed up"
} else {
    $Result = "FAILED - $Failures of $Jobs folder(s) had errors"
}

Set-Content -Path (Join-Path $AgentDir 'status.txt') -Value @(
    "Last run : $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Result   : $Result",
    "Log      : $Log"
)
Write-Log "Finished: $Result"

if ($Failures -eq 0) { Send-Ping '' } else { Send-Ping '/fail' }
Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
if ($Failures -eq 0) { exit 0 } else { exit 1 }

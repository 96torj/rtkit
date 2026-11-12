# ==========================================================
#  BackupAgent uninstaller (run as Administrator)
#  Removes the scheduled task and C:\BackupAgent.
#  Files already in the cloud are NOT deleted.
# ==========================================================
$TaskName = 'BackupAgent'
$AgentDir = 'C:\BackupAgent'

$ok = Read-Host "Remove BackupAgent from this PC? Cloud files stay. (Y/N)"
if ($ok -notmatch '^[Yy]') { exit 0 }

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Scheduled task removed."

# Run from a temp copy so this script can delete its own folder
Set-Location $env:TEMP
Remove-Item $AgentDir -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $AgentDir) {
    Write-Host "Could not fully delete $AgentDir. Delete it by hand."
} else {
    Write-Host "$AgentDir deleted."
}
Read-Host "Press Enter to close"

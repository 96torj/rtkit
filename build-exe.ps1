# Builds RTKit.exe from RTKit.ps1 (run on YOUR PC, in the RTKit folder)
# Right-click > Run with PowerShell, or:  powershell -ExecutionPolicy Bypass -File .\build-exe.ps1
Set-Location $PSScriptRoot
if (-not (Get-Module -ListAvailable ps2exe)) {
    Write-Host "Installing ps2exe (one time)..."
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe
Invoke-ps2exe -inputFile .\RTKit.ps1 -outputFile .\RTKit.exe `
    -noConsole -requireAdmin -STA -iconFile .\rtkit.ico `
    -title 'RT Kit' -product 'RT Kit' -company 'Ryan Torres' -version '1.0.0' -copyright '(c) Ryan Torres'
if (Test-Path .\RTKit.exe) { Write-Host "Built RTKit.exe" -ForegroundColor Green } else { Write-Host "Build failed" -ForegroundColor Red }
Read-Host "Press Enter to close"

# ==========================================================
#  RT Kit - client PC toolkit (GUI)
#  Backup to USB, cloud backup agent, encrypted cloud vault,
#  virus scan, disk cleaner, network checker, firewall.
#  Run with RTKit.bat (asks for admin).
#  Needs Windows 10/11, PowerShell 5.1 (.NET 4.7.2+). Not for WinRE.
# ==========================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------------------------------------------------
#  Theme (dark / minimal)
# ----------------------------------------------------------
$Clr = @{
    Bg      = [System.Drawing.ColorTranslator]::FromHtml('#0B0F14')
    Panel   = [System.Drawing.ColorTranslator]::FromHtml('#11171F')
    Input   = [System.Drawing.ColorTranslator]::FromHtml('#161E28')
    Border  = [System.Drawing.ColorTranslator]::FromHtml('#243040')
    Text    = [System.Drawing.ColorTranslator]::FromHtml('#E6EDF3')
    Muted   = [System.Drawing.ColorTranslator]::FromHtml('#7D8A99')
    Accent  = [System.Drawing.ColorTranslator]::FromHtml('#00D4FF')
    AccentD = [System.Drawing.ColorTranslator]::FromHtml('#0A3A4A')
    Danger  = [System.Drawing.ColorTranslator]::FromHtml('#FF5C6C')
    Ok      = [System.Drawing.ColorTranslator]::FromHtml('#3DDC97')
    Warn    = [System.Drawing.ColorTranslator]::FromHtml('#FFB547')
    Term    = [System.Drawing.ColorTranslator]::FromHtml('#7EE8FA')
}
$FontUi    = New-Object System.Drawing.Font('Segoe UI', 9.5)
$FontBold  = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
$FontBig   = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$FontLogo  = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$FontMono  = New-Object System.Drawing.Font('Consolas', 9.5)

# Dark title bar (Windows 10 2004+ / 11)
try {
    Add-Type -Namespace RTKit -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);' -ErrorAction Stop
} catch { }
function Set-DarkTitle($Form) {
    try { $v = 1; [void][RTKit.Dwm]::DwmSetWindowAttribute($Form.Handle, 20, [ref]$v, 4) } catch { }
}

function Set-Theme($Ctrl) {
    foreach ($c in $Ctrl.Controls) {
        switch ($c.GetType().Name) {
            'Button' {
                $c.FlatStyle = 'Flat'
                $c.Cursor = 'Hand'
                $c.FlatAppearance.BorderSize = 1
                if ($c.Tag -eq 'big') {
                    $c.BackColor = $Clr.Accent; $c.ForeColor = $Clr.Bg
                    $c.FlatAppearance.BorderColor = $Clr.Accent
                    $c.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml('#5BE6FF')
                    $c.Font = $FontBig
                } elseif ($c.Tag -eq 'danger') {
                    $c.BackColor = $Clr.Panel; $c.ForeColor = $Clr.Danger
                    $c.FlatAppearance.BorderColor = $Clr.Danger
                    $c.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml('#2A1418')
                    $c.Font = $FontUi
                } elseif ($c.Tag -eq 'nav') {
                    # styled by the sidebar code
                } else {
                    $c.BackColor = $Clr.Input; $c.ForeColor = $Clr.Text
                    $c.FlatAppearance.BorderColor = $Clr.Border
                    $c.FlatAppearance.MouseOverBackColor = $Clr.AccentD
                    $c.Font = $FontUi
                }
            }
            'TextBox' {
                if ($c -ne $logBox) {
                    $c.BackColor = $Clr.Input; $c.ForeColor = $Clr.Text; $c.BorderStyle = 'FixedSingle'; $c.Font = $FontUi
                }
            }
            'ComboBox'        { $c.FlatStyle = 'Flat'; $c.BackColor = $Clr.Input; $c.ForeColor = $Clr.Text; $c.Font = $FontUi }
            'ListBox'         { $c.BackColor = $Clr.Input; $c.ForeColor = $Clr.Text; $c.BorderStyle = 'FixedSingle'; $c.Font = $FontUi }
            'CheckedListBox'  { $c.BackColor = $Clr.Input; $c.ForeColor = $Clr.Text; $c.BorderStyle = 'FixedSingle'; $c.Font = $FontUi }
            'CheckBox'        { $c.ForeColor = $Clr.Text; $c.FlatStyle = 'Flat'; $c.Font = $FontUi; $c.BackColor = [System.Drawing.Color]::Transparent }
            'Label' {
                if (-not $c.Tag) { $c.ForeColor = $Clr.Muted; $c.Font = $FontUi }
                $c.BackColor = [System.Drawing.Color]::Transparent
            }
            'Panel' { Set-Theme $c }
        }
    }
}

$AppName   = 'RT Kit'
# Works as a script (.ps1) and as a compiled RTKit.exe
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$Rclone    = Join-Path $Root 'bin\rclone.exe'
$AgentSrc  = Join-Path $Root 'agent'
$ToolsDir  = Join-Path $Root 'tools'
$VaultDir  = Join-Path $Root 'vault'
$ReportDir = Join-Path $Root 'reports'
$UserFile  = Join-Path $Root 'rtkit-user.json'
$AgentDir  = 'C:\BackupAgent'
$TaskName  = 'BackupAgent'
$MpCmd     = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
$Iter      = 200000

New-Item -ItemType Directory -Force -Path $VaultDir, $ReportDir | Out-Null
# Keep a login made with the older TechKit version
$oldUser = Join-Path $Root 'techkit-user.json'
if (-not (Test-Path $UserFile) -and (Test-Path $oldUser)) { Rename-Item $oldUser $UserFile }

$Script:EncKey = $null
$Script:MacKey = $null

# ----------------------------------------------------------
#  Crypto: PBKDF2-SHA256 -> AES-256-CBC + HMAC-SHA256
# ----------------------------------------------------------
function Get-DerivedKeys([string]$Password, [byte[]]$Salt, [int]$Iterations) {
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $b = $kdf.GetBytes(96)
    $kdf.Dispose()
    return @{ Enc = [byte[]]$b[0..31]; Mac = [byte[]]$b[32..63]; Ver = [byte[]]$b[64..95] }
}

function Protect-Bytes([byte[]]$Plain) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $Script:EncKey
    $aes.GenerateIV()
    $ct = $aes.CreateEncryptor().TransformFinalBlock($Plain, 0, $Plain.Length)
    $data = [byte[]]($aes.IV + $ct)
    $aes.Dispose()
    $tag = [System.Security.Cryptography.HMACSHA256]::new($Script:MacKey).ComputeHash($data)
    return [byte[]]($data + $tag)
}

function Unprotect-Bytes([byte[]]$Blob) {
    if ($Blob.Length -lt 64) { throw 'File too small or damaged.' }
    $data = [byte[]]$Blob[0..($Blob.Length - 33)]
    $tag  = [byte[]]$Blob[($Blob.Length - 32)..($Blob.Length - 1)]
    $check = [System.Security.Cryptography.HMACSHA256]::new($Script:MacKey).ComputeHash($data)
    if ([Convert]::ToBase64String($check) -ne [Convert]::ToBase64String($tag)) {
        throw 'Config failed the integrity check (wrong login or file changed).'
    }
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $Script:EncKey
    $aes.IV = [byte[]]$data[0..15]
    $ct = [byte[]]$data[16..($data.Length - 1)]
    $plain = $aes.CreateDecryptor().TransformFinalBlock($ct, 0, $ct.Length)
    $aes.Dispose()
    return $plain
}

# ----------------------------------------------------------
#  UI helpers
# ----------------------------------------------------------
function Show-Msg([string]$Text, [string]$Icon = 'Information') {
    [System.Windows.Forms.MessageBox]::Show($Text, $AppName, 'OK', $Icon) | Out-Null
}
function Ask-YesNo([string]$Text) {
    return ([System.Windows.Forms.MessageBox]::Show($Text, $AppName, 'YesNo', 'Question') -eq 'Yes')
}
function Clean-Name([string]$Name) { return ($Name -replace '[^A-Za-z0-9_-]', '') }

function New-Label($Text, $X, $Y, $W = 140, $H = 22) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = New-Object System.Drawing.Point($X, $Y); $l.Size = New-Object System.Drawing.Size($W, $H)
    return $l
}
function New-Button($Text, $X, $Y, $W = 160, $H = 34) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Location = New-Object System.Drawing.Point($X, $Y); $b.Size = New-Object System.Drawing.Size($W, $H)
    return $b
}
function New-BigButton($Text, $X, $Y, $W = 220, $H = 50) {
    $b = New-Button $Text $X $Y $W $H
    $b.Tag = 'big'
    return $b
}
function New-DangerButton($Text, $X, $Y, $W = 160, $H = 34) {
    $b = New-Button $Text $X $Y $W $H
    $b.Tag = 'danger'
    return $b
}
function New-TextBox($X, $Y, $W = 220, $Text = '') {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y); $t.Size = New-Object System.Drawing.Size($W, 22); $t.Text = $Text
    return $t
}
function New-Check($Text, $X, $Y, $W = 330, $Checked = $false) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Location = New-Object System.Drawing.Point($X, $Y); $c.Size = New-Object System.Drawing.Size($W, 22); $c.Checked = $Checked
    return $c
}
$Script:Pages = New-Object System.Collections.ArrayList
$Script:NavButtons = New-Object System.Collections.ArrayList
function New-Tab($Text) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point(205, 104)
    $p.Size = New-Object System.Drawing.Size(755, 320)
    $p.BackColor = $Clr.Bg
    $p.Visible = ($Script:Pages.Count -eq 0)
    $main.Controls.Add($p)
    $idx = $Script:Pages.Count
    [void]$Script:Pages.Add(@{ Panel = $p; Title = $Text })

    $b = New-Object System.Windows.Forms.Button
    $b.Tag = 'nav'
    $b.Text = "   $Text"
    $b.TextAlign = 'MiddleLeft'
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $Clr.Input
    $b.Font = $FontUi; $b.Cursor = 'Hand'
    $b.Location = New-Object System.Drawing.Point(0, (24 + $idx * 44))
    $b.Size = New-Object System.Drawing.Size(185, 40)
    $b.Name = "nav$idx"
    $b.Add_Click({ Select-Page ([int]($this.Name.Substring(3))) })
    $sidebar.Controls.Add($b)
    [void]$Script:NavButtons.Add($b)
    Select-Page 0
    return $p
}
function Select-Page([int]$Index) {
    for ($i = 0; $i -lt $Script:Pages.Count; $i++) {
        $on = ($i -eq $Index)
        $Script:Pages[$i].Panel.Visible = $on
        $nb = $Script:NavButtons[$i]
        if ($on) {
            $nb.BackColor = $Clr.AccentD; $nb.ForeColor = $Clr.Accent; $nb.Font = $FontBold
        } else {
            $nb.BackColor = $Clr.Panel; $nb.ForeColor = $Clr.Muted; $nb.Font = $FontUi
        }
    }
    $lblPage.Text = $Script:Pages[$Index].Title.ToUpper()
}

# ----------------------------------------------------------
#  Login / first-time setup
# ----------------------------------------------------------
function Show-LoginForm {
    $firstRun = -not (Test-Path $UserFile)

    $f = New-Object System.Windows.Forms.Form
    $f.Text = "$AppName - Login"
    $f.Size = New-Object System.Drawing.Size(380, $(if ($firstRun) { 270 } else { 220 }))
    $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.TopMost = $true

    $f.Controls.Add((New-Label $(if ($firstRun) { "First run: create your $AppName login" } else { "Sign in to unlock $AppName" }) 20 15 330))
    $f.Controls.Add((New-Label 'Username' 20 50 100))
    $tUser = New-TextBox 130 48 210
    $f.Controls.Add($tUser)
    $f.Controls.Add((New-Label 'Password' 20 85 100))
    $tPass = New-TextBox 130 83 210
    $tPass.UseSystemPasswordChar = $true
    $f.Controls.Add($tPass)

    $tConfirm = $null
    $y = 125
    if ($firstRun) {
        $f.Controls.Add((New-Label 'Confirm' 20 120 100))
        $tConfirm = New-TextBox 130 118 210
        $tConfirm.UseSystemPasswordChar = $true
        $f.Controls.Add($tConfirm)
        $y = 165
    }

    $btn = New-Button $(if ($firstRun) { 'Create login' } else { 'Sign in' }) 130 $y 210 36
    $btn.Tag = 'big'
    $f.Controls.Add($btn)
    $f.BackColor = $Clr.Bg; $f.ForeColor = $Clr.Text; $f.Font = $FontUi
    Set-Theme $f
    $f.Controls[0].ForeColor = $Clr.Accent; $f.Controls[0].Font = $FontBold
    $f.Add_Shown({ Set-DarkTitle $f })
    $f.AcceptButton = $btn
    $Script:LoginOk = $false

    $btn.Add_Click({
        $u = $tUser.Text.Trim()
        $p = $tPass.Text
        if (-not $u -or -not $p) { Show-Msg 'Enter a username and password.' 'Warning'; return }
        $f.Cursor = 'WaitCursor'
        try {
            if ($firstRun) {
                if ($p.Length -lt 10) { Show-Msg 'Use at least 10 characters.' 'Warning'; return }
                if ($p -ne $tConfirm.Text) { Show-Msg 'Passwords do not match.' 'Warning'; return }
                $salt = New-Object byte[] 16
                [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
                $k = Get-DerivedKeys $p $salt $Iter
                [ordered]@{
                    User = $u; Salt = [Convert]::ToBase64String($salt); Iterations = $Iter
                    Verifier = [Convert]::ToBase64String($k.Ver)
                } | ConvertTo-Json | Set-Content -Path $UserFile
                $Script:EncKey = $k.Enc; $Script:MacKey = $k.Mac
                Show-Msg "Login created.`n`nIf you forget this password, the configs in the vault cannot be recovered."
                $Script:LoginOk = $true; $f.Close()
            } else {
                $info = Get-Content $UserFile -Raw | ConvertFrom-Json
                $k = Get-DerivedKeys $p ([Convert]::FromBase64String($info.Salt)) ([int]$info.Iterations)
                if ($u -ne $info.User -or [Convert]::ToBase64String($k.Ver) -ne $info.Verifier) {
                    Show-Msg 'Wrong username or password.' 'Error'
                    $tPass.Text = ''
                    return
                }
                $Script:EncKey = $k.Enc; $Script:MacKey = $k.Mac
                $Script:LoginOk = $true; $f.Close()
            }
        } finally { $f.Cursor = 'Default' }
    })

    [void]$f.ShowDialog()
    return $Script:LoginOk
}

if (-not (Show-LoginForm)) { exit }

# ----------------------------------------------------------
#  Main window
# ----------------------------------------------------------
$main = New-Object System.Windows.Forms.Form
$main.Text = "$AppName   |   $env:COMPUTERNAME"
$main.ClientSize = New-Object System.Drawing.Size(980, 690)
$main.StartPosition = 'CenterScreen'
$main.FormBorderStyle = 'FixedSingle'; $main.MaximizeBox = $false
$main.BackColor = $Clr.Bg; $main.ForeColor = $Clr.Text; $main.Font = $FontUi

# Header bar
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0); $header.Size = New-Object System.Drawing.Size(980, 60)
$header.BackColor = $Clr.Panel
$main.Controls.Add($header)

$lblLogo = New-Object System.Windows.Forms.Label
$lblLogo.Tag = 'keep'; $lblLogo.Text = 'RT KIT'; $lblLogo.Font = $FontLogo; $lblLogo.ForeColor = $Clr.Accent
$lblLogo.Location = New-Object System.Drawing.Point(20, 14); $lblLogo.Size = New-Object System.Drawing.Size(110, 34)
$header.Controls.Add($lblLogo)
$lblSub = New-Label "// $env:COMPUTERNAME" 128 23 220
$header.Controls.Add($lblSub)

$lblClient = New-Label 'CLIENT' 380 22 55
$header.Controls.Add($lblClient)
$tClient = New-TextBox 438 18 200
$header.Controls.Add($tClient)

$lblBusy = New-Object System.Windows.Forms.Label
$lblBusy.Tag = 'keep'; $lblBusy.Text = "$([char]0x25CF)  READY"; $lblBusy.ForeColor = $Clr.Ok; $lblBusy.Font = $FontBold
$lblBusy.Location = New-Object System.Drawing.Point(665, 21); $lblBusy.Size = New-Object System.Drawing.Size(300, 24)
$lblBusy.TextAlign = 'MiddleRight'
$header.Controls.Add($lblBusy)

# Accent line under the header
$line = New-Object System.Windows.Forms.Panel
$line.Location = New-Object System.Drawing.Point(0, 60); $line.Size = New-Object System.Drawing.Size(980, 1); $line.BackColor = $Clr.AccentD
$main.Controls.Add($line)

# Sidebar
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Location = New-Object System.Drawing.Point(0, 61); $sidebar.Size = New-Object System.Drawing.Size(185, 629)
$sidebar.BackColor = $Clr.Panel
$main.Controls.Add($sidebar)
$lblVer = New-Label 'v1.0  signed in' 18 600 160
$sidebar.Controls.Add($lblVer)

# Page title
$lblPage = New-Object System.Windows.Forms.Label
$lblPage.Tag = 'keep'; $lblPage.Font = $FontBold; $lblPage.ForeColor = $Clr.Text
$lblPage.Location = New-Object System.Drawing.Point(205, 74); $lblPage.Size = New-Object System.Drawing.Size(500, 24)
$main.Controls.Add($lblPage)

# Output console
$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Tag = 'keep'; $lblOut.Text = 'OUTPUT'; $lblOut.Font = $FontBold; $lblOut.ForeColor = $Clr.Muted
$lblOut.Location = New-Object System.Drawing.Point(205, 432); $lblOut.Size = New-Object System.Drawing.Size(200, 22)
$main.Controls.Add($lblOut)
$btnClearLog = New-Button 'Clear' 890 428 70 26
$main.Controls.Add($btnClearLog)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ScrollBars = 'Vertical'; $logBox.ReadOnly = $true
$logBox.Font = $FontMono; $logBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#06090D'); $logBox.ForeColor = $Clr.Term
$logBox.BorderStyle = 'FixedSingle'
$logBox.Location = New-Object System.Drawing.Point(205, 458)
$logBox.Size = New-Object System.Drawing.Size(755, 215)
$main.Controls.Add($logBox)
$btnClearLog.Add_Click({ $logBox.Clear() })

function Write-UiLog([string]$Msg) {
    if ($logBox.TextLength -gt 200000) { $logBox.Text = $logBox.Text.Substring(100000) }
    $logBox.AppendText("$Msg`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-ClientName {
    $c = Clean-Name $tClient.Text
    if (-not $c) { $c = 'NoClient' }
    return $c
}

function Save-Report([string]$Action, [string[]]$Lines) {
    $client = Get-ClientName
    $file = Join-Path $ReportDir ("{0}_{1}_{2}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'), $client, $Action)
    $head = @("$AppName report", "Client : $client", "Action : $Action", "PC     : $env:COMPUTERNAME", "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "")
    Set-Content -Path $file -Value ($head + $Lines)
    Write-UiLog "Report saved: $file"
    return $file
}

# ----------------------------------------------------------
#  Background job runner (one job at a time, output tailed into the log box)
# ----------------------------------------------------------
$Script:Run = $null
$runTimer = New-Object System.Windows.Forms.Timer
$runTimer.Interval = 1000

function Read-RunLog {
    $r = $Script:Run
    if (-not $r -or -not (Test-Path $r.Log)) { return }
    try {
        $fs = New-Object System.IO.FileStream($r.Log, 'Open', 'Read', 'ReadWrite')
        [void]$fs.Seek($r.Pos, 'Begin')
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Default)
        $new = $sr.ReadToEnd()
        $r.Pos = $fs.Position
        $sr.Close(); $fs.Close()
        if ($new) {
            $clean = ($new -split "`r?`n" | Where-Object { $_ -notlike '##*' }) -join "`r`n"
            if ($clean.Trim()) { $logBox.AppendText($clean.TrimEnd() + "`r`n") }
        }
    } catch { }
}

$runTimer.Add_Tick({
    $r = $Script:Run
    if (-not $r) { $runTimer.Stop(); return }
    Read-RunLog
    if ($r.Proc.HasExited) {
        $runTimer.Stop()
        Start-Sleep -Milliseconds 300
        Read-RunLog
        $Script:Run = $null
        $lblBusy.Text = "$([char]0x25CF)  READY"; $lblBusy.ForeColor = $Clr.Ok
        Write-UiLog "=== $($r.Title) finished ==="
        $lines = @(Get-Content $r.Log -ErrorAction SilentlyContinue)
        if ($r.OnDone) { & $r.OnDone $r.Data $lines }
    }
})

function Start-Runner([string]$Title, [string[]]$Lines, [string]$Log, [scriptblock]$OnDone, $Data = $null) {
    if ($Script:Run) { Show-Msg "Please wait: '$($Script:Run.Title)' is still running." 'Warning'; return $false }
    if (Test-Path $Log) { Remove-Item $Log -Force -ErrorAction SilentlyContinue }
    $cmdFile = Join-Path $env:TEMP ("rtkit_{0}.cmd" -f [guid]::NewGuid())
    Set-Content -Path $cmdFile -Value (@('@echo off') + $Lines + "echo ##DONE>>`"$Log`"") -Encoding Default
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$cmdFile`"" -WindowStyle Hidden -PassThru
    $Script:Run = @{ Proc = $p; Log = $Log; Pos = 0; OnDone = $OnDone; Title = $Title; Data = $Data }
    $lblBusy.Text = "$([char]0x25CF)  RUNNING: $($Title.ToUpper())"; $lblBusy.ForeColor = $Clr.Warn
    Write-UiLog "=== $Title started ==="
    $runTimer.Start()
    return $true
}

function Get-ToolLog([string]$Name) { return (Join-Path $env:TEMP "rtkit_$Name.log") }
function Get-PsLine([string]$Script, [string]$ScriptArgs, [string]$Log) {
    return "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Script`" $ScriptArgs >> `"$Log`" 2>&1"
}

# ----------------------------------------------------------
#  Vault
# ----------------------------------------------------------
function Get-VaultNames {
    Get-ChildItem $VaultDir -Filter '*.conf.enc' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name -replace '\.conf\.enc$', '' } | Sort-Object
}
function Save-ToVault([string]$Name, [byte[]]$Plain) {
    [IO.File]::WriteAllBytes((Join-Path $VaultDir "$Name.conf.enc"), (Protect-Bytes $Plain))
}
function Read-FromVault([string]$Name) {
    return Unprotect-Bytes ([IO.File]::ReadAllBytes((Join-Path $VaultDir "$Name.conf.enc")))
}

$Skip = @('Public','Default','Default User','All Users','defaultuser0','WDAGUtilityAccount')

# ==========================================================
#  TAB: USB Backup
# ==========================================================
$tabUsb = New-Tab 'USB Backup'

$tabUsb.Controls.Add((New-Label 'Windows drive' 15 20))
$cbSrc = New-Object System.Windows.Forms.ComboBox
$cbSrc.DropDownStyle = 'DropDownList'; $cbSrc.Location = New-Object System.Drawing.Point(160, 18); $cbSrc.Size = New-Object System.Drawing.Size(230, 22)
$tabUsb.Controls.Add($cbSrc)

$tabUsb.Controls.Add((New-Label 'Backup drive' 15 55))
$cbDst = New-Object System.Windows.Forms.ComboBox
$cbDst.DropDownStyle = 'DropDownList'; $cbDst.Location = New-Object System.Drawing.Point(160, 53); $cbDst.Size = New-Object System.Drawing.Size(230, 22)
$tabUsb.Controls.Add($cbDst)

$chkOneDrive = New-Check 'Include OneDrive folder' 160 88 230
$tabUsb.Controls.Add($chkOneDrive)

$tabUsb.Controls.Add((New-Label 'Users to back up' 420 20 200))
$clUsers = New-Object System.Windows.Forms.CheckedListBox
$clUsers.Location = New-Object System.Drawing.Point(420, 45); $clUsers.Size = New-Object System.Drawing.Size(295, 190)
$clUsers.CheckOnClick = $true
$tabUsb.Controls.Add($clUsers)

$btnRefresh  = New-Button 'Refresh drives' 15 130 140
$btnStartUsb = New-BigButton 'START BACKUP' 160 130 230
$tabUsb.Controls.Add($btnRefresh); $tabUsb.Controls.Add($btnStartUsb)
$tabUsb.Controls.Add((New-Label 'Enter the client name at the top first. Do not unplug drives while running.' 15 250 700))

function Update-Drives {
    $cbSrc.Items.Clear(); $cbDst.Items.Clear()
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $letter = $d.Name.Substring(0, 2)
        $text = "{0}  {1}  ({2} GB free)" -f $letter, $d.VolumeLabel, [math]::Round($d.AvailableFreeSpace / 1GB)
        if (Test-Path "$letter\Users") { [void]$cbSrc.Items.Add($text) }
        if ($d.DriveType -ne 'CDRom') { [void]$cbDst.Items.Add($text) }
    }
    if ($cbSrc.Items.Count -gt 0) { $cbSrc.SelectedIndex = 0 }
    for ($i = 0; $i -lt $cbDst.Items.Count; $i++) { if ($cbDst.Items[$i] -match 'BACKUP') { $cbDst.SelectedIndex = $i } }
}
function Update-Users {
    $clUsers.Items.Clear()
    if (-not $cbSrc.SelectedItem) { return }
    $letter = $cbSrc.SelectedItem.ToString().Substring(0, 2)
    Get-ChildItem "$letter\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $Skip -notcontains $_.Name } |
        ForEach-Object { [void]$clUsers.Items.Add($_.Name, $true) }
}
$cbSrc.Add_SelectedIndexChanged({ Update-Users })
$btnRefresh.Add_Click({ Update-Drives; Update-Users })

$btnStartUsb.Add_Click({
    if (-not $cbSrc.SelectedItem -or -not $cbDst.SelectedItem) { Show-Msg 'Pick both drives.' 'Warning'; return }
    $src = $cbSrc.SelectedItem.ToString().Substring(0, 2)
    $dst = $cbDst.SelectedItem.ToString().Substring(0, 2)
    if ($src -eq $dst) { Show-Msg 'The backup drive cannot be the Windows drive.' 'Warning'; return }
    if (-not (Clean-Name $tClient.Text)) { Show-Msg 'Enter the client name at the top.' 'Warning'; return }
    $client = Get-ClientName
    $users = @($clUsers.CheckedItems | ForEach-Object { $_.ToString() })
    if ($users.Count -eq 0) { Show-Msg 'Tick at least one user.' 'Warning'; return }

    $destRoot = "$dst\Backups\${client}_$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
    New-Item -ItemType Directory -Force -Path "$destRoot\Users", "$destRoot\Extras" | Out-Null
    $log = "$destRoot\backup_log.txt"

    try {
        Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
            Where-Object DisplayName | Sort-Object DisplayName -Unique |
            Select-Object DisplayName, DisplayVersion, Publisher |
            Format-Table -AutoSize | Out-String -Width 300 | Set-Content "$destRoot\Extras\installed_programs.txt"
    } catch { }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("systeminfo > `"$destRoot\Extras\system_info.txt`" 2>nul")
    foreach ($u in $users) {
        $s = "$src\Users\$u"
        $xd = "`"$s\AppData\Local\Temp`" `"$s\AppData\Local\Microsoft\Windows\INetCache`" `"$s\AppData\Local\CrashDumps`" `"$s\AppData\Local\Google\Chrome\User Data\Default\Cache`" `"$s\AppData\Local\Microsoft\Edge\User Data\Default\Cache`""
        if (-not $chkOneDrive.Checked) { $xd += " `"$s\OneDrive`"" }
        $lines.Add("echo ===== Backing up $u =====>>`"$log`"")
        $lines.Add("robocopy `"$s`" `"$destRoot\Users\$u`" /E /ZB /COPY:DAT /DCOPY:T /XJ /R:1 /W:1 /MT:8 /NP /NDL /LOG+:`"$log`" /XD $xd /XF NTUSER.DAT* ntuser.dat.LOG* UsrClass.dat* *.tmp")
        $lines.Add("if errorlevel 8 (echo ##FAIL $u>>`"$log`") else (echo ##OK $u>>`"$log`")")
    }

    $data = @{ Source = "$src\Users"; Dest = $destRoot; Users = $users; Log = $log }
    $done = {
        param($d, $out)
        $fails = @($out | Where-Object { $_ -like '##FAIL*' })
        $result = if ($fails.Count -eq 0) { 'OK - no copy errors' } else { "WARNING - $($fails.Count) user(s) had errors (search the log for ERROR)" }
        $rep = Save-Report 'USB-Backup' @("Source : $($d.Source)", "Dest   : $($d.Dest)", "Users  : $($d.Users -join ', ')", "Result : $result", "Log    : $($d.Log)")
        Show-Msg "Backup finished.`n`n$result`n`nSaved to: $($d.Dest)"
    }
    # The robocopy log lives on the backup drive; the runner tails it
    [void](Start-Runner 'USB backup' $lines $log $done $data)
})

# ==========================================================
#  TAB: Backup Agent
# ==========================================================
$tabAgent = New-Tab 'Backup Agent'

$tabAgent.Controls.Add((New-Label 'Cloud config (vault)' 15 20))
$cbVault = New-Object System.Windows.Forms.ComboBox
$cbVault.DropDownStyle = 'DropDownList'; $cbVault.Location = New-Object System.Drawing.Point(160, 18); $cbVault.Size = New-Object System.Drawing.Size(230, 22)
$tabAgent.Controls.Add($cbVault)

$tabAgent.Controls.Add((New-Label 'Backup time (HH:mm)' 15 55))
$tTime = New-TextBox 160 53 80 '02:00'
$tabAgent.Controls.Add($tTime)

$tabAgent.Controls.Add((New-Label 'Healthcheck URL' 15 90))
$tHealth = New-TextBox 160 88 230
$tabAgent.Controls.Add($tHealth)

$tabAgent.Controls.Add((New-Label 'Extra folders (one per line, e.g. C:\ClientData)' 420 20 300))
$tExtra = New-Object System.Windows.Forms.TextBox
$tExtra.Multiline = $true; $tExtra.ScrollBars = 'Vertical'
$tExtra.Location = New-Object System.Drawing.Point(420, 45); $tExtra.Size = New-Object System.Drawing.Size(295, 90)
$tabAgent.Controls.Add($tExtra)

$btnInstall = New-BigButton 'INSTALL AGENT' 160 140 230
$btnStatus  = New-Button 'Check status' 420 150 140
$btnRunNow  = New-Button 'Run backup now' 575 150 140
$btnRemove  = New-DangerButton 'Remove agent' 420 195 140
$tabAgent.Controls.AddRange(@($btnInstall, $btnStatus, $btnRunNow, $btnRemove))
$tabAgent.Controls.Add((New-Label 'Uses the client name at the top. The cloud config must contain a remote named clientbackup.' 15 250 700))

$cbVault.Add_SelectedIndexChanged({ if (-not $tClient.Text) { $tClient.Text = $cbVault.SelectedItem } })

$btnInstall.Add_Click({
    if (-not $cbVault.SelectedItem) { Show-Msg 'Pick a cloud config. Add one in the Cloud Vault tab first.' 'Warning'; return }
    if (-not (Clean-Name $tClient.Text)) { Show-Msg 'Enter the client name at the top.' 'Warning'; return }
    $client = Get-ClientName
    if ($tTime.Text -notmatch '^\d{1,2}:\d{2}$') { Show-Msg 'Time must look like 02:00' 'Warning'; return }
    if (-not (Test-Path $Rclone)) { Show-Msg "rclone.exe missing in $Root\bin" 'Error'; return }
    if (-not (Ask-YesNo "Install the backup agent on THIS PC ($env:COMPUTERNAME) for client '$client'?")) { return }

    $main.Cursor = 'WaitCursor'
    try {
        Write-UiLog "Installing agent for $client..."
        New-Item -ItemType Directory -Force -Path $AgentDir, "$AgentDir\logs" | Out-Null
        & icacls $AgentDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /T /Q | Out-Null
        Write-UiLog "Folder locked to SYSTEM + Administrators"

        [IO.File]::WriteAllBytes("$AgentDir\rclone.conf", (Read-FromVault $cbVault.SelectedItem))
        Copy-Item $Rclone "$AgentDir\rclone.exe" -Force
        Copy-Item "$AgentSrc\backup-agent.ps1" "$AgentDir\backup-agent.ps1" -Force
        if (Test-Path "$AgentSrc\uninstall-agent.ps1") { Copy-Item "$AgentSrc\uninstall-agent.ps1" "$AgentDir\uninstall-agent.ps1" -Force }

        $extra = @($tExtra.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        [ordered]@{
            ClientName = $client; Remote = 'clientbackup'
            Folders = @('Desktop','Documents','Pictures','Videos','Music','Downloads')
            ExtraPaths = $extra; KeepVersionsDays = 30
            BackupTime = $tTime.Text; HealthcheckUrl = $tHealth.Text.Trim()
        } | ConvertTo-Json | Set-Content "$AgentDir\settings.json"
        Write-UiLog "Files and settings written"

        Write-UiLog "Testing cloud connection..."
        & "$AgentDir\rclone.exe" lsd 'clientbackup:' --config "$AgentDir\rclone.conf" --max-depth 1 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Cannot reach remote 'clientbackup'. Check the config and the internet." }
        Write-UiLog "Cloud connection OK"

        $psArgs    = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\BackupAgent\backup-agent.ps1"'
        $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs
        $trigger   = New-ScheduledTaskTrigger -Daily -At $tTime.Text
        $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $taskSet   = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -AllowStartIfOnBatteries `
                     -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 12) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
            -Settings $taskSet -Description 'Nightly cloud backup of user folders (rclone)' -Force | Out-Null
        Write-UiLog "Scheduled task created: every day at $($tTime.Text)"

        [void](Save-Report 'Agent-Install' @("Config : $($cbVault.SelectedItem)", "Time   : $($tTime.Text) daily", "Extra  : $($extra -join '; ')"))
        if (Ask-YesNo "Agent installed.`n`nRun the first backup now? (It can take hours the first time.)") {
            Start-ScheduledTask -TaskName $TaskName
            Write-UiLog "First backup started in the background"
        }
    } catch {
        Write-UiLog "ERROR: $_"
        Show-Msg "Install failed:`n$_" 'Error'
    } finally { $main.Cursor = 'Default' }
})

$btnStatus.Add_Click({
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { Write-UiLog 'Agent is NOT installed on this PC.'; return }
    $ti = $task | Get-ScheduledTaskInfo
    Write-UiLog '----- Agent status -----'
    Write-UiLog "Task state : $($task.State)"
    Write-UiLog "Last run   : $($ti.LastRunTime)"
    Write-UiLog "Next run   : $($ti.NextRunTime)"
    if (Test-Path "$AgentDir\status.txt") { Get-Content "$AgentDir\status.txt" | ForEach-Object { Write-UiLog $_ } }
    else { Write-UiLog 'No status.txt yet (no backup has finished).' }
})

$btnRunNow.Add_Click({
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) { Write-UiLog 'Agent is NOT installed.'; return }
    Start-ScheduledTask -TaskName $TaskName
    Write-UiLog 'Backup started in the background. Use Check status later.'
})

$btnRemove.Add_Click({
    if (-not (Ask-YesNo 'Remove the backup agent from this PC? Files already in the cloud are kept.')) { return }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $AgentDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $AgentDir) { Write-UiLog "Could not fully delete $AgentDir" } else { Write-UiLog 'Agent removed.'; [void](Save-Report 'Agent-Remove' @('Agent removed from this PC.')) }
})

# ==========================================================
#  TAB: Cloud Vault
# ==========================================================
$tabVault = New-Tab 'Cloud Vault'

$tabVault.Controls.Add((New-Label 'Encrypted cloud configs (one per client). Each must contain a remote named  clientbackup' 15 15 700))
$lbVault = New-Object System.Windows.Forms.ListBox
$lbVault.Location = New-Object System.Drawing.Point(15, 45); $lbVault.Size = New-Object System.Drawing.Size(300, 230)
$tabVault.Controls.Add($lbVault)

$btnNewCfg    = New-Button 'New config (rclone setup)' 340 45 260
$btnImportCfg = New-Button 'Import an rclone.conf file' 340 90 260
$btnTestCfg   = New-Button 'Test selected config' 340 135 260
$btnDelCfg    = New-DangerButton 'Delete selected config' 340 180 260
$tabVault.Controls.AddRange(@($btnNewCfg, $btnImportCfg, $btnTestCfg, $btnDelCfg))

function Update-VaultLists {
    $cbVault.Items.Clear(); $lbVault.Items.Clear()
    foreach ($n in @(Get-VaultNames)) { [void]$cbVault.Items.Add($n); [void]$lbVault.Items.Add($n) }
}

function Add-ConfigToVault([string]$PlainPath) {
    $text = Get-Content $PlainPath -Raw
    if ($text -notmatch '(?m)^\[clientbackup\]') {
        if (-not (Ask-YesNo "This config has no remote named 'clientbackup'. The agent will not work with it. Save anyway?")) { return }
    }
    $name = Clean-Name ([Microsoft.VisualBasic.Interaction]::InputBox('Client name for this config (no spaces):', $AppName, (Clean-Name $tClient.Text)))
    if (-not $name) { return }
    if ((Test-Path (Join-Path $VaultDir "$name.conf.enc")) -and -not (Ask-YesNo "'$name' already exists. Replace it?")) { return }
    Save-ToVault $name ([IO.File]::ReadAllBytes($PlainPath))
    Write-UiLog "Saved encrypted config: $name"
    Update-VaultLists
}

$btnNewCfg.Add_Click({
    if (-not (Test-Path $Rclone)) { Show-Msg "rclone.exe missing in $Root\bin" 'Error'; return }
    Show-Msg "A setup window will open.`n`n1. Type n (new remote)`n2. Name it:  clientbackup`n3. Answer the questions for the cloud (OneDrive, Google Drive, B2...)`n4. Type q to quit when done.`n`n$AppName will then encrypt it into the vault."
    $tmp = Join-Path $env:TEMP ("rtkit_{0}.conf" -f [guid]::NewGuid())
    Start-Process -FilePath $Rclone -ArgumentList @('config', '--config', "`"$tmp`"") -Wait
    if (Test-Path $tmp) {
        try { Add-ConfigToVault $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    } else { Write-UiLog 'No config was created.' }
})

$btnImportCfg.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'rclone config (*.conf)|*.conf|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    Add-ConfigToVault $dlg.FileName
    if (Ask-YesNo "Delete the unencrypted original?`n$($dlg.FileName)") {
        Remove-Item $dlg.FileName -Force -ErrorAction SilentlyContinue
        Write-UiLog 'Original deleted.'
    }
})

$btnTestCfg.Add_Click({
    if (-not $lbVault.SelectedItem) { Show-Msg 'Select a config first.' 'Warning'; return }
    $tmp = Join-Path $env:TEMP ("rtkit_{0}.conf" -f [guid]::NewGuid())
    try {
        [IO.File]::WriteAllBytes($tmp, (Read-FromVault $lbVault.SelectedItem))
        Write-UiLog "Testing $($lbVault.SelectedItem)..."
        & $Rclone lsd 'clientbackup:' --config $tmp --max-depth 1 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-UiLog 'Connection OK' } else { Write-UiLog 'Connection FAILED' }
    } catch { Write-UiLog "ERROR: $_" }
    finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
})

$btnDelCfg.Add_Click({
    if (-not $lbVault.SelectedItem) { return }
    if (Ask-YesNo "Delete config '$($lbVault.SelectedItem)' from the vault?") {
        Remove-Item (Join-Path $VaultDir "$($lbVault.SelectedItem).conf.enc") -Force
        Write-UiLog "Deleted $($lbVault.SelectedItem)"
        Update-VaultLists
    }
})

# ==========================================================
#  TAB: Virus Scan (Microsoft Defender)
# ==========================================================
$tabVirus = New-Tab 'Virus Scan'

$btnAvStatus  = New-Button 'Antivirus status' 15 20 200
$btnAvUpdate  = New-Button 'Update virus definitions' 15 65 200
$btnAvQuick   = New-BigButton 'QUICK SCAN' 240 20 220
$btnAvFull    = New-Button 'Full scan (can take hours)' 240 80 220
$btnAvFolder  = New-Button 'Scan a folder or USB...' 240 125 220
$btnAvThreats = New-Button 'Show threats found' 490 20 220
$btnAvOffline = New-DangerButton 'Offline scan (restarts PC)' 490 65 220
$tabVirus.Controls.AddRange(@($btnAvStatus, $btnAvUpdate, $btnAvQuick, $btnAvFull, $btnAvFolder, $btnAvThreats, $btnAvOffline))
$tabVirus.Controls.Add((New-Label 'Uses Microsoft Defender, built into Windows. If the client has another antivirus (Norton, McAfee...), Defender may be off: use that antivirus instead.' 15 190 700 40))

function Test-Defender {
    if (-not (Test-Path $MpCmd)) { Show-Msg 'Microsoft Defender was not found on this PC.' 'Error'; return $false }
    return $true
}

$avDone = {
    param($d, $out)
    $text = ($out -join "`n")
    $clean = $text -match 'found no threats'
    $result = if ($d.Kind -eq 'Update') { 'Definitions update finished' } elseif ($clean) { 'No threats found' } else { 'Scan finished - check results / threats' }
    [void](Save-Report "Virus-$($d.Kind)" (@("Result : $result", '', 'Output:') + $out))
    if (-not $clean -and $d.Kind -ne 'Update') {
        try {
            $det = @(Get-MpThreatDetection -ErrorAction Stop | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10)
            if ($det.Count) {
                Write-UiLog 'Recent detections:'
                $det | ForEach-Object { Write-UiLog ("  {0}  {1}" -f $_.InitialDetectionTime, ($_.Resources -join '; ')) }
            }
        } catch { }
    }
    Show-Msg $result
}

$btnAvStatus.Add_Click({
    Write-UiLog '----- Antivirus status -----'
    try {
        Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
            ForEach-Object { Write-UiLog "Installed antivirus : $($_.displayName)" }
    } catch { }
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop
        Write-UiLog "Defender mode       : $($s.AMRunningMode)"
        Write-UiLog "Real-time protection: $($s.RealTimeProtectionEnabled)"
        Write-UiLog "Definitions updated : $($s.AntivirusSignatureLastUpdated)"
        Write-UiLog "Last quick scan     : $($s.QuickScanEndTime)"
        Write-UiLog "Last full scan      : $($s.FullScanEndTime)"
    } catch { Write-UiLog "Could not read Defender status: $($_.Exception.Message)" }
})

$btnAvUpdate.Add_Click({
    if (-not (Test-Defender)) { return }
    $log = Get-ToolLog 'av'
    [void](Start-Runner 'Definitions update' @("`"$MpCmd`" -SignatureUpdate >> `"$log`" 2>&1") $log $avDone @{ Kind = 'Update' })
})
$btnAvQuick.Add_Click({
    if (-not (Test-Defender)) { return }
    $log = Get-ToolLog 'av'
    [void](Start-Runner 'Quick scan' @("`"$MpCmd`" -SignatureUpdate >> `"$log`" 2>&1", "`"$MpCmd`" -Scan -ScanType 1 >> `"$log`" 2>&1") $log $avDone @{ Kind = 'QuickScan' })
})
$btnAvFull.Add_Click({
    if (-not (Test-Defender)) { return }
    if (-not (Ask-YesNo 'A full scan can take 1-3 hours. Start it?')) { return }
    $log = Get-ToolLog 'av'
    [void](Start-Runner 'Full scan' @("`"$MpCmd`" -SignatureUpdate >> `"$log`" 2>&1", "`"$MpCmd`" -Scan -ScanType 2 >> `"$log`" 2>&1") $log $avDone @{ Kind = 'FullScan' })
})
$btnAvFolder.Add_Click({
    if (-not (Test-Defender)) { return }
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Pick a folder or drive to scan'
    if ($fb.ShowDialog() -ne 'OK') { return }
    $log = Get-ToolLog 'av'
    [void](Start-Runner "Scan $($fb.SelectedPath)" @("`"$MpCmd`" -Scan -ScanType 3 -File `"$($fb.SelectedPath)`" >> `"$log`" 2>&1") $log $avDone @{ Kind = 'FolderScan' })
})
$btnAvThreats.Add_Click({
    Write-UiLog '----- Threat history -----'
    try {
        $det = @(Get-MpThreatDetection -ErrorAction Stop | Sort-Object InitialDetectionTime -Descending | Select-Object -First 20)
        if (-not $det.Count) { Write-UiLog 'No threats recorded.'; return }
        $names = @{}
        Get-MpThreat -ErrorAction SilentlyContinue | ForEach-Object { $names[$_.ThreatID] = $_.ThreatName }
        foreach ($t in $det) {
            Write-UiLog ("{0}  {1}  action:{2}" -f $t.InitialDetectionTime, $names[$t.ThreatID], $t.ThreatStatusID)
            Write-UiLog ("    {0}" -f ($t.Resources -join '; '))
        }
    } catch { Write-UiLog "Could not read threats: $($_.Exception.Message)" }
})
$btnAvOffline.Add_Click({
    if (-not (Ask-YesNo "Offline scan RESTARTS the PC in about a minute and scans before Windows loads (about 15 min).`n`nSave the client's work first. Continue?")) { return }
    try { Start-MpWDOScan -ErrorAction Stop; [void](Save-Report 'Virus-OfflineScan' @('Offline scan started, PC restarting.')); Write-UiLog 'Offline scan scheduled. The PC will restart.' }
    catch { Show-Msg "Could not start offline scan: $($_.Exception.Message)" 'Error' }
})

# ==========================================================
#  TAB: Disk Cleaner
# ==========================================================
$tabDisk = New-Tab 'Disk Cleaner'

$chkUserTemp  = New-Check 'User temp files (all users)' 15 20 330 $true
$chkWinTemp   = New-Check 'Windows temp files' 15 48 330 $true
$chkRecycle   = New-Check 'Empty Recycle Bin (all users) - ask the client first!' 15 76 360 $false
$chkUpdate    = New-Check 'Windows Update download cache' 15 104 330 $true
$chkDelivery  = New-Check 'Delivery Optimization cache' 15 132 330 $true
$chkThumbs    = New-Check 'Thumbnail cache' 15 160 330 $true
$chkBrowser   = New-Check 'Browser caches (close browsers first; logins are kept)' 15 188 370 $false
$chkComponent = New-Check 'Component store cleanup (DISM, slow: 5-20 min)' 15 216 370 $false
$tabDisk.Controls.AddRange(@($chkUserTemp, $chkWinTemp, $chkRecycle, $chkUpdate, $chkDelivery, $chkThumbs, $chkBrowser, $chkComponent))

$btnDiskSpace = New-Button 'Show disk space' 420 20 200
$btnClean     = New-BigButton 'CLEAN NOW' 420 70 220
$tabDisk.Controls.AddRange(@($btnDiskSpace, $btnClean))
$tabDisk.Controls.Add((New-Label 'Never touches Documents, Desktop, Pictures or Downloads.' 420 135 300 40))

$btnDiskSpace.Add_Click({
    Write-UiLog '----- Disk space -----'
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.IsReady -and $d.DriveType -in 'Fixed', 'Removable') {
            $pct = [math]::Round(100 * $d.AvailableFreeSpace / $d.TotalSize)
            Write-UiLog ("{0}  {1,-12} {2,7} GB free of {3,7} GB  ({4}% free)" -f $d.Name, $d.VolumeLabel, [math]::Round($d.AvailableFreeSpace / 1GB, 1), [math]::Round($d.TotalSize / 1GB, 1), $pct)
        }
    }
})

$btnClean.Add_Click({
    $sw = @()
    if ($chkUserTemp.Checked)  { $sw += '-UserTemp' }
    if ($chkWinTemp.Checked)   { $sw += '-WinTemp' }
    if ($chkRecycle.Checked)   { $sw += '-RecycleBin' }
    if ($chkUpdate.Checked)    { $sw += '-UpdateCache' }
    if ($chkDelivery.Checked)  { $sw += '-DeliveryOpt' }
    if ($chkThumbs.Checked)    { $sw += '-Thumbnails' }
    if ($chkBrowser.Checked)   { $sw += '-BrowserCache' }
    if ($chkComponent.Checked) { $sw += '-ComponentStore' }
    if ($sw.Count -eq 0) { Show-Msg 'Tick at least one item.' 'Warning'; return }
    if ($chkRecycle.Checked -and -not (Ask-YesNo 'Empty the Recycle Bin for ALL users? Did the client agree?')) { return }
    $log = Get-ToolLog 'clean'
    $done = {
        param($d, $out)
        $freed = ($out | Where-Object { $_ -like '##FREED*' } | Select-Object -First 1) -replace '##FREED ', ''
        [void](Save-Report 'Disk-Clean' (@("Freed  : $freed", '', 'Output:') + ($out | Where-Object { $_ -notlike '##*' })))
        Show-Msg "Cleanup finished.`n`nSpace freed on C: about $freed"
    }
    [void](Start-Runner 'Disk cleanup' @(Get-PsLine (Join-Path $ToolsDir 'disk-clean.ps1') ($sw -join ' ') $log) $log $done)
})

# ==========================================================
#  TAB: Network
# ==========================================================
$tabNet = New-Tab 'Network'

$btnNetCheck = New-BigButton 'CHECK NETWORK' 15 20 230
$btnNetRepair = New-DangerButton 'Network reset (repair)' 15 90 230
$btnNetIp = New-Button 'Show full IP config' 270 20 200
$btnNetDnsFlush = New-Button 'Flush DNS cache' 270 65 200
$tabNet.Controls.AddRange(@($btnNetCheck, $btnNetRepair, $btnNetIp, $btnNetDnsFlush))
$tabNet.Controls.Add((New-Label "Check tests: adapter, IP/DHCP, router, internet, DNS and web, then says where the problem is.`nNetwork reset clears DNS, renews the IP and resets Winsock/TCP-IP. A restart is needed after." 15 150 700 50))

$btnNetCheck.Add_Click({
    $log = Get-ToolLog 'net'
    $done = {
        param($d, $out)
        $ok = [bool]($out | Where-Object { $_ -eq '##NET OK' })
        [void](Save-Report 'Network-Check' ($out | Where-Object { $_ -notlike '##*' }))
        Show-Msg $(if ($ok) { 'Network check: everything looks good.' } else { 'Network check found problems. See the Result section in the log.' }) $(if ($ok) { 'Information' } else { 'Warning' })
    }
    [void](Start-Runner 'Network check' @(Get-PsLine (Join-Path $ToolsDir 'net-check.ps1') '' $log) $log $done)
})

$btnNetRepair.Add_Click({
    if (-not (Ask-YesNo "Reset the network?`n`nThe PC will briefly lose connection, and a restart is needed after.`nSaved Wi-Fi networks are kept.")) { return }
    $log = Get-ToolLog 'netreset'
    $lines = @(
        "echo [Flush DNS]>>`"$log`"", "ipconfig /flushdns >> `"$log`" 2>&1",
        "echo [Release IP]>>`"$log`"", "ipconfig /release >> `"$log`" 2>&1",
        "echo [Renew IP]>>`"$log`"", "ipconfig /renew >> `"$log`" 2>&1",
        "echo [Winsock reset]>>`"$log`"", "netsh winsock reset >> `"$log`" 2>&1",
        "echo [TCP/IP reset]>>`"$log`"", "netsh int ip reset >> `"$log`" 2>&1"
    )
    $done = {
        param($d, $out)
        [void](Save-Report 'Network-Reset' ($out | Where-Object { $_ -notlike '##*' }))
        if (Ask-YesNo "Network reset done. Restart the PC now?") { Restart-Computer -Force }
    }
    [void](Start-Runner 'Network reset' $lines $log $done)
})

$btnNetIp.Add_Click({ Write-UiLog '----- ipconfig /all -----'; (ipconfig /all) | ForEach-Object { Write-UiLog $_ } })
$btnNetDnsFlush.Add_Click({ (ipconfig /flushdns) | ForEach-Object { if ($_.Trim()) { Write-UiLog $_ } } })

# ==========================================================
#  TAB: Firewall
# ==========================================================
$tabFw = New-Tab 'Firewall'

$tabFw.Controls.Add((New-Label 'Profile' 15 22 60))
$cbFwProfile = New-Object System.Windows.Forms.ComboBox
$cbFwProfile.DropDownStyle = 'DropDownList'; $cbFwProfile.Location = New-Object System.Drawing.Point(80, 20); $cbFwProfile.Size = New-Object System.Drawing.Size(150, 22)
@('All', 'Domain', 'Private', 'Public') | ForEach-Object { [void]$cbFwProfile.Items.Add($_) }
$cbFwProfile.SelectedIndex = 0
$tabFw.Controls.Add($cbFwProfile)

$btnFwStatus = New-Button 'Show status' 260 15 160
$btnFwOn     = New-BigButton 'TURN ON' 15 70 200
$btnFwOff    = New-DangerButton 'Turn OFF' 230 78 160
$btnFwReset  = New-DangerButton 'Reset to Windows defaults' 15 140 240
$btnFwOpen   = New-Button 'Open advanced firewall' 270 140 200
$tabFw.Controls.AddRange(@($btnFwStatus, $btnFwOn, $btnFwOff, $btnFwReset, $btnFwOpen))
$tabFw.Controls.Add((New-Label "Domain = work network, Private = home, Public = cafes/hotels.`nOnly turn it off to test a problem, and turn it back on before you leave." 15 200 700 50))

function Get-FwProfiles { if ($cbFwProfile.SelectedItem -eq 'All') { return @('Domain', 'Private', 'Public') } else { return @($cbFwProfile.SelectedItem) } }
function Show-FwStatus {
    Write-UiLog '----- Firewall status -----'
    Get-NetFirewallProfile | ForEach-Object {
        Write-UiLog ("{0,-8} {1}" -f $_.Name, $(if ($_.Enabled) { 'ON' } else { 'OFF  <-- not protected' }))
    }
    try {
        Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName FirewallProduct -ErrorAction Stop |
            ForEach-Object { Write-UiLog "Third-party firewall: $($_.displayName)" }
    } catch { }
}

$btnFwStatus.Add_Click({ Show-FwStatus })
$btnFwOn.Add_Click({
    $p = Get-FwProfiles
    Set-NetFirewallProfile -Profile $p -Enabled True
    Write-UiLog "Firewall turned ON for: $($p -join ', ')"
    [void](Save-Report 'Firewall-On' @("Profiles : $($p -join ', ')"))
    Show-FwStatus
})
$btnFwOff.Add_Click({
    $p = Get-FwProfiles
    if (-not (Ask-YesNo "Turn the firewall OFF for: $($p -join ', ')?`n`nThe PC is less protected until you turn it back on.")) { return }
    Set-NetFirewallProfile -Profile $p -Enabled False
    Write-UiLog "Firewall turned OFF for: $($p -join ', ')  - remember to turn it back on"
    [void](Save-Report 'Firewall-Off' @("Profiles : $($p -join ', ')", 'WARNING: firewall left OFF at time of report'))
    Show-FwStatus
})
$btnFwReset.Add_Click({
    if (-not (Ask-YesNo "Reset ALL firewall rules to Windows defaults?`n`nCustom rules (game servers, printers, remote tools) will be removed.")) { return }
    $out = netsh advfirewall reset
    Write-UiLog "Firewall reset: $($out -join ' ')"
    [void](Save-Report 'Firewall-Reset' @('Firewall rules reset to Windows defaults.'))
    Show-FwStatus
})
$btnFwOpen.Add_Click({ Start-Process 'wf.msc' })

# ----------------------------------------------------------
#  Start
# ----------------------------------------------------------
$main.Add_FormClosing({
    $e = $_
    if ($Script:Run -and -not $Script:Run.Proc.HasExited) {
        if (-not (Ask-YesNo "'$($Script:Run.Title)' is still running. Close anyway? (It keeps going in the background.)")) { $e.Cancel = $true; return }
    }
    try {
        if (Get-NetFirewallProfile | Where-Object { -not $_.Enabled }) {
            if (-not (Ask-YesNo 'The firewall is still OFF on at least one profile. Close anyway?')) { $e.Cancel = $true; return }
        }
    } catch { }
    $Script:EncKey = $null; $Script:MacKey = $null
})

Set-Theme $main
foreach ($pg in $Script:Pages) { Set-Theme $pg.Panel }
Select-Page 0
$main.Add_Shown({ Set-DarkTitle $main })

Update-Drives
Update-Users
Update-VaultLists
Write-UiLog "$AppName ready. Signed in. Running on $env:COMPUTERNAME"
[void]$main.ShowDialog()

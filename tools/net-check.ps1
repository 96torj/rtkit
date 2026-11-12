# RT Kit - Network Checker (output goes to the RT Kit log)
function Say([string]$m) { [Console]::Out.WriteLine($m) }

function Test-Ping([string]$Target, [string]$Label) {
    $r = @(Test-Connection -ComputerName $Target -Count 4 -ErrorAction SilentlyContinue)
    if ($r.Count -gt 0) {
        $avg = [math]::Round(($r | Measure-Object ResponseTime -Average).Average)
        Say ("  {0,-28} OK    {1}/4 replies, avg {2} ms" -f $Label, $r.Count, $avg)
        return $true
    }
    Say ("  {0,-28} FAIL  no replies" -f $Label)
    return $false
}

$problems = New-Object System.Collections.Generic.List[string]

Say "[Adapters that are connected]"
$ad = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
if ($ad.Count -eq 0) { Say "  NONE"; $problems.Add('No network adapter is connected (cable unplugged, Wi-Fi off, or driver problem).') }
foreach ($a in $ad) { Say ("  {0,-20} {1,-12} {2}" -f $a.Name, $a.LinkSpeed, $a.InterfaceDescription) }

$wifi = netsh wlan show interfaces 2>$null | Select-String -Pattern '^\s*(SSID|Signal)\s*:'
if ($wifi) {
    Say ""
    Say "[Wi-Fi]"
    $wifi | ForEach-Object { Say ("  " + $_.Line.Trim()) }
}

Say ""
Say "[IP configuration]"
$cfg = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.NetAdapter.Status -eq 'Up' })
$gateway = $null
foreach ($c in $cfg) {
    $ip  = ($c.IPv4Address | Select-Object -First 1).IPAddress
    $gw  = ($c.IPv4DefaultGateway | Select-Object -First 1).NextHop
    $dns = ($c.DNSServer | Where-Object AddressFamily -eq 2 | ForEach-Object { $_.ServerAddresses }) -join ', '
    Say ("  {0}: IP {1}  Gateway {2}  DNS {3}" -f $c.InterfaceAlias, $ip, $gw, $dns)
    if ($ip -like '169.254.*') { $problems.Add("$($c.InterfaceAlias) has a 169.254 address: it did not get an IP from the router (DHCP problem).") }
    if ($gw -and -not $gateway) { $gateway = $gw }
}
if (-not $gateway) { $problems.Add('No default gateway: the PC is not talking to a router.') }

Say ""
Say "[Ping tests]"
$gwOk = $false
if ($gateway) { $gwOk = Test-Ping $gateway "Router ($gateway)" }
$net1 = Test-Ping '1.1.1.1' 'Internet (1.1.1.1)'
$net2 = Test-Ping '8.8.8.8' 'Internet (8.8.8.8)'

Say ""
Say "[DNS test]"
$dnsOk = $false
try {
    $res = Resolve-DnsName 'www.microsoft.com' -Type A -ErrorAction Stop | Where-Object IPAddress | Select-Object -First 1
    Say "  www.microsoft.com -> $($res.IPAddress)   OK"
    $dnsOk = $true
} catch { Say "  Could not resolve www.microsoft.com   FAIL" }

Say ""
Say "[Web test]"
$webOk = $false
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $w = Invoke-WebRequest 'https://www.microsoft.com' -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    $sw.Stop()
    Say "  HTTPS www.microsoft.com -> $($w.StatusCode) in $($sw.ElapsedMilliseconds) ms   OK"
    $webOk = $true
} catch { Say "  HTTPS test FAIL: $($_.Exception.Message)" }

# ---- Diagnosis ----
if ($gateway -and -not $gwOk -and -not ($net1 -or $net2)) { $problems.Add('Cannot reach the router. Check the cable / Wi-Fi, then restart the router.') }
elseif ($gwOk -and -not ($net1 -or $net2)) { $problems.Add('Router OK but no internet: the problem is the router/modem or the internet provider.') }
if (($net1 -or $net2) -and -not $dnsOk) { $problems.Add('Internet works but DNS fails: try Network Reset, or set DNS to 1.1.1.1 / 8.8.8.8.') }
if ($dnsOk -and -not $webOk) { $problems.Add('DNS works but websites fail: check proxy settings, VPN, firewall or antivirus web filter.') }

Say ""
Say "[Result]"
if ($problems.Count -eq 0) {
    Say "  Everything looks good."
    Say "##NET OK"
} else {
    foreach ($p in $problems) { Say "  - $p" }
    Say "##NET PROBLEMS $($problems.Count)"
}

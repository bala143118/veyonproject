<#
.SYNOPSIS
    Tests network reachability and Veyon port connectivity to target client computers.

.DESCRIPTION
    Performs ICMP ping and TCP socket probes on port 11100 (Veyon Server) and 11200 (VNC)
    for each target computer. Distinguishes between firewall blocks, ICMP drops, and port listeners.
    Returns structured results.

.PARAMETER TargetHost
    One or more hostnames or IP addresses to test.

.PARAMETER TimeoutMs
    Connection timeout in milliseconds (default: 1200).

.PARAMETER JsonOutput
    Outputs results strictly as JSON for automated parsing.

.EXAMPLE
    .\Test-VeyonConnectivity.ps1 -TargetHost "127.0.0.1", "192.168.1.101"
    .\Test-VeyonConnectivity.ps1 -TargetHost "127.0.0.1" -JsonOutput
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string[]]$TargetHost,

    [Parameter()]
    [int]$TimeoutMs = 1200,

    [Parameter()]
    [switch]$JsonOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Test-TcpPort([string]$hostName, [int]$port, [int]$timeout) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($hostName, $port, $null, $null)
        $wh = $iar.AsyncWaitHandle
        $connected = $wh.WaitOne($timeout, $false)
        if ($connected) {
            $client.EndConnect($iar)
            $sw.Stop()
            $client.Close()
            return @{ Open = $true; LatencyMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1) }
        } else {
            $sw.Stop()
            $client.Close()
            return @{ Open = $false; LatencyMs = -1 }
        }
    } catch {
        $sw.Stop()
        $client.Close()
        return @{ Open = $false; LatencyMs = -1 }
    }
}

$results = @()

foreach ($h in $TargetHost) {
    $cleanHost = $h.Trim()
    if (-not $cleanHost) { continue }

    # Validate host format
    if ($cleanHost -notmatch '^[a-zA-Z0-9_\-\.]+$') {
        $results += [PSCustomObject]@{
            Host = $cleanHost
            State = "CHECK FAILED"
            PingOk = $false
            PingMs = -1
            Port11100Open = $false
            Port11100Ms = -1
            Port11200Open = $false
            Error = "Invalid hostname or IP address format"
            Timestamp = (Get-Date).ToString("o")
        }
        continue
    }

    # 1. ICMP Ping
    $pingOk = $false
    $pingMs = -1
    try {
        $pingObj = New-Object System.Net.NetworkInformation.Ping
        $reply = $pingObj.Send($cleanHost, $TimeoutMs)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            $pingOk = $true
            $pingMs = $reply.RoundtripTime
        }
    } catch {}

    # 2. Port 11100 (Veyon Server)
    $port11100 = Test-TcpPort $cleanHost 11100 $TimeoutMs

    # 3. Port 11200 (VNC Server)
    $port11200 = Test-TcpPort $cleanHost 11200 $TimeoutMs

    # Determine State
    $state = "UNKNOWN"
    if ($port11100.Open) {
        $state = "CONNECTED"
    } elseif ($pingOk -and -not $port11100.Open) {
        $state = "DISCONNECTED" # Machine is up, but Veyon service is not listening
    } elseif (-not $pingOk -and -not $port11100.Open) {
        $state = "DISCONNECTED" # Machine unreachable
    }

    $resObj = [PSCustomObject]@{
        Host = $cleanHost
        State = $state
        PingOk = $pingOk
        PingMs = $pingMs
        Port11100Open = $port11100.Open
        Port11100Ms = $port11100.LatencyMs
        Port11200Open = $port11200.Open
        Error = $null
        Timestamp = (Get-Date).ToString("o")
    }

    $results += $resObj

    if (-not $JsonOutput) {
        $color = if ($state -eq "CONNECTED") { "Green" } else { "Yellow" }
        Write-Host "[$state] $cleanHost -> Ping: $(if($pingOk){"$pingMs ms"}else{"Failed"}) | Port 11100: $(if($port11100.Open){"Open ($($port11100.LatencyMs) ms)"}else{"Closed"})" -ForegroundColor $color
    }
}

if ($JsonOutput) {
    return ($results | ConvertTo-Json -Depth 3)
}

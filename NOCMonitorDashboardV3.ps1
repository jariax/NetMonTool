# =====================================================
# NOC MONITOR - SINGLE WINDOW TV DASHBOARD
# Purpose:
#   Real-time single-pane network health dashboard
# Layout:
#   5 columns x 3 rows for NOC TV display
#
# Background Fix:
#   Forces the default console background to black and
#   prevents white-on-white display issues.
# =====================================================

# =====================================================
# CONFIGURATION - NODE LIST
# Replace these IPs with your real destination IPs.
# =====================================================

$Nodes = @(
    @{ ID = 1;  NodeName = "NODE_1";  IP = "1.1.1.1"  },
    @{ ID = 2;  NodeName = "NODE_2";  IP = "1.1.1.1"  },
    @{ ID = 3;  NodeName = "NODE_3";  IP = "1.1.1.1" },
    @{ ID = 4;  NodeName = "NODE_4";  IP = "1.1.1.1" },
    @{ ID = 5;  NodeName = "NODE_5";  IP = "1.1.1.1" },
    @{ ID = 6;  NodeName = "NODE_6";  IP = "1.1.1.1" },
    @{ ID = 7;  NodeName = "NODE_7";  IP = "1.1.1.1" },
    @{ ID = 8;  NodeName = "NODE_8";  IP = "1.1.1.1" },
    @{ ID = 9;  NodeName = "NODE_9";  IP = "8.8.8.8" },
    @{ ID = 10; NodeName = "NODE_10"; IP = "8.8.8.8" },
    @{ ID = 11; NodeName = "NODE_11"; IP = "8.8.8.8" },
    @{ ID = 12; NodeName = "NODE_12"; IP = "8.8.8.8" },
    @{ ID = 13; NodeName = "NODE_13"; IP = "8.8.8.8" },
    @{ ID = 14; NodeName = "NODE_14"; IP = "8.8.8.8" },
    @{ ID = 15; NodeName = "NODE_15"; IP = "8.8.8.8" }
)

# =====================================================
# UPDATE TIMING NOTE
# =====================================================
# This dashboard uses sequential polling.
#
# That means the script pings each node one at a time, updates
# the node state, then redraws the dashboard. After all nodes are
# checked, the script waits for the value configured in:
#
#   $RefreshIntervalSeconds
#
# Current intended settings:
#   $PingTimeoutMs = 2500
#   $RefreshIntervalSeconds = 2
#
# Important:
#   $RefreshIntervalSeconds does NOT mean every node is guaranteed
#   to be pinged exactly every 2 seconds.
#
# The real dashboard update cycle is approximately:
#
#   Time to ping all nodes + $RefreshIntervalSeconds
#
# Example:
#   - If all 15 nodes respond quickly, updates may happen close to
#     every 2-4 seconds.
#   - If 1 node times out, that node can add up to 2.5 seconds.
#   - If 5 nodes time out, they can add up to 12.5 seconds.
#   - If all 15 nodes time out, the cycle can take about 37.5 seconds
#     plus the 2-second refresh interval.
#
# Anything over $PingTimeoutMs is treated as a timeout.
#
# For true "every node every 2 seconds" behavior, the script would
# need to be upgraded from sequential polling to parallel polling.
# =====================================================

# =====================================================
# MONITORING THRESHOLDS
# =====================================================

$FailThreshold = 3
$LatencyThresholdMs = 500
$LossThresholdPercent = 20

# Jitter is displayed for visibility and baseline collection only.
# It does NOT currently affect node color/status.
# Once a reliable jitter baseline is established, it can be added
# back into the DEGRADED logic.
# $JitterThresholdMs = 50

$PingTimeoutMs = 2500
$RefreshIntervalSeconds = 2
$HistoryLimit = 10

# =====================================================
# DASHBOARD LAYOUT - NOC TV SETTING
# =====================================================

$Columns = 5
$Rows = 3

# Tile width includes borders.
$TileWidth = 34

# Space between tiles.
$TileGap = "    "

# Console size for wide TV display.
# Width should be enough for:
# 5 tiles * 34 chars = 170
# 4 gaps * 4 chars = 16
# Total around 186+
$ConsoleWidth = 200
$ConsoleHeight = 45

# =====================================================
# DEFAULT CONSOLE COLORS
# =====================================================

$DefaultBackgroundColor = "Black"
$DefaultForegroundColor = "White"

# =====================================================
# INITIAL SETUP
# =====================================================

$Host.UI.RawUI.WindowTitle = "NOC SINGLE PANE TV DASHBOARD"

try {
    $raw = $Host.UI.RawUI

    # Force default console colors.
    $raw.BackgroundColor = $DefaultBackgroundColor
    $raw.ForegroundColor = $DefaultForegroundColor

    $bufferSize = $raw.BufferSize
    $windowSize = $raw.WindowSize

    # Buffer must be at least as large as the window.
    $bufferSize.Width = $ConsoleWidth
    $bufferSize.Height = 500

    $windowSize.Width = $ConsoleWidth
    $windowSize.Height = $ConsoleHeight

    $raw.BufferSize = $bufferSize
    $raw.WindowSize = $windowSize

    Clear-Host
}
catch {
    # Console resize may fail depending on terminal.
    # Monitoring will still run.
}

# Stores per-node health state
$NodeState = @{}

foreach ($node in $Nodes) {
    $NodeState[$node.ID] = @{
        LatencyHistory      = @()
        PingHistory         = @()
        ConsecutiveFails    = 0
        LastSuccessfulPing  = "N/A"
        CurrentLatency      = $null
        AvgLatency          = "N/A"
        LossPercent         = 0
        Jitter              = "N/A"
        Status              = "INIT"
        BgColor             = "DarkCyan"
    }
}

# =====================================================
# FUNCTION: SAFE BACKGROUND COLOR
# Purpose:
#   Prevents white/blank/default background issues.
#
# CHANGE 1: DEGRADED now uses DarkMagenta instead of
#   DarkYellow so it is visually distinct from WARNING
#   on the NOC TV display.
# =====================================================

function Get-SafeBgColor {
    param (
        [string]$Status
    )

    switch ($Status) {
        "UP"       { return "DarkGreen" }
        "WARNING"  { return "DarkYellow" }
        "DEGRADED" { return "DarkMagenta" }
        "DOWN"     { return "DarkRed" }
        "INIT"     { return "DarkCyan" }
        default    { return "Black" }
    }
}

# =====================================================
# FUNCTION: PING NODE
# =====================================================

function Test-NodePing {
    param (
        [string]$IP,
        [int]$TimeoutMs
    )

    $ping = New-Object System.Net.NetworkInformation.Ping

    try {
        $reply = $ping.Send($IP, $TimeoutMs)

        if ($reply.Status -eq "Success") {
            return @{
                Success = $true
                Latency = [int]$reply.RoundtripTime
            }
        }
        else {
            return @{
                Success = $false
                Latency = $null
            }
        }
    }
    catch {
        return @{
            Success = $false
            Latency = $null
        }
    }
    finally {
        $ping.Dispose()
    }
}

# =====================================================
# FUNCTION: UPDATE NODE STATE
# =====================================================

function Update-NodeState {
    param (
        [hashtable]$Node
    )

    $id = $Node.ID
    $ip = $Node.IP
    $state = $NodeState[$id]

    # Full date/time for LAST OK
    # Shorter option if needed: Get-Date -Format "MM/dd HH:mm:ss"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $result = Test-NodePing -IP $ip -TimeoutMs $PingTimeoutMs

    if ($result.Success) {
        $state.CurrentLatency = $result.Latency
        $state.ConsecutiveFails = 0
        $state.LastSuccessfulPing = $timestamp

        $state.LatencyHistory += $result.Latency
        $state.PingHistory += $true
    }
    else {
        $state.CurrentLatency = $null
        $state.ConsecutiveFails++
        $state.PingHistory += $false
    }

    # Keep only latest successful latency values
    if ($state.LatencyHistory.Count -gt $HistoryLimit) {
        $state.LatencyHistory = $state.LatencyHistory[-$HistoryLimit..-1]
    }

    # Keep only latest ping attempts
    if ($state.PingHistory.Count -gt $HistoryLimit) {
        $state.PingHistory = $state.PingHistory[-$HistoryLimit..-1]
    }

    # Average latency and jitter are based only on successful replies
    if ($state.LatencyHistory.Count -gt 0) {
        $state.AvgLatency = [math]::Round(($state.LatencyHistory | Measure-Object -Average).Average, 1)

        $maxLatency = ($state.LatencyHistory | Measure-Object -Maximum).Maximum
        $minLatency = ($state.LatencyHistory | Measure-Object -Minimum).Minimum

        $state.Jitter = $maxLatency - $minLatency
    }
    else {
        $state.AvgLatency = "N/A"
        $state.Jitter = "N/A"
    }

    # Packet loss based on last X ping attempts
    if ($state.PingHistory.Count -gt 0) {
        $lossCount = ($state.PingHistory | Where-Object { $_ -eq $false }).Count
        $state.LossPercent = [math]::Round(($lossCount / $state.PingHistory.Count) * 100, 0)
    }
    else {
        $state.LossPercent = 0
    }

    # =====================================================
    # HEALTH STATUS LOGIC
    # =====================================================
    # Color/status changes are based on:
    #   1. Consecutive failed pings
    #   2. Average latency
    #   3. Packet loss
    #
    # Jitter is displayed, but it does not affect color/status yet.
    # =====================================================

    if ($state.ConsecutiveFails -ge $FailThreshold) {
        $state.Status = "DOWN"
        $state.BgColor = "DarkRed"
    }
    elseif ($state.ConsecutiveFails -gt 0) {
        $state.Status = "WARNING"
        $state.BgColor = "DarkYellow"
    }
    elseif (
        ($state.AvgLatency -ne "N/A" -and $state.AvgLatency -gt $LatencyThresholdMs) -or
        ($state.LossPercent -gt $LossThresholdPercent)
    ) {
        $state.Status = "DEGRADED"
        $state.BgColor = "DarkMagenta"
    }
    else {
        $state.Status = "UP"
        $state.BgColor = "DarkGreen"
    }

    $NodeState[$id] = $state
}

# =====================================================
# FUNCTION: FORMAT TILE LINE
# =====================================================

function Format-TileLine {
    param (
        [string]$Text
    )

    $InnerWidth = $TileWidth - 4

    if ($Text.Length -gt $InnerWidth) {
        $Text = $Text.Substring(0, $InnerWidth)
    }

    return "| " + $Text.PadRight($InnerWidth) + " |"
}

# =====================================================
# FUNCTION: GET TILE LINES
# CHANGE 2: AVG10 and JITTER display "N/A" cleanly
#   instead of "N/Ams" when no data is available.
# =====================================================

function Get-NodeTileLines {
    param (
        [hashtable]$Node
    )

    $state = $NodeState[$Node.ID]

    if ($null -ne $state.CurrentLatency) {
        $currentText = "$($state.CurrentLatency)ms"
    }
    else {
        $currentText = "TIMEOUT"
    }

    # Display "N/A" cleanly — do not append "ms" when value is not numeric
    if ($state.AvgLatency -eq "N/A") {
        $avgText = "N/A"
    }
    else {
        $avgText = "$($state.AvgLatency)ms"
    }

    if ($state.Jitter -eq "N/A") {
        $jitterText = "N/A"
    }
    else {
        $jitterText = "$($state.Jitter)ms"
    }

    $lines = @(
        "$($Node.NodeName)",
        "IP     : $($Node.IP)",
        "STATUS : $($state.Status)",
        "CURR   : $currentText",
        "AVG10  : $avgText",
        "LOSS10 : $($state.LossPercent)%",
        "JITTER : $jitterText",
        "FAILS  : $($state.ConsecutiveFails)",
        "LAST OK: $($state.LastSuccessfulPing)"
    )

    return $lines
}

# =====================================================
# FUNCTION: WRITE TILE GAP
# Purpose:
#   Keeps spacing between node boxes black.
# =====================================================

function Write-TileGap {
    Write-Host $TileGap `
        -ForegroundColor $DefaultForegroundColor `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline
}

# =====================================================
# FUNCTION: WRITE DASHBOARD
# CHANGE 3: Renamed from Draw-Dashboard to
#   Write-Dashboard. "Draw" is not an approved
#   PowerShell verb; "Write" is the correct choice.
# CHANGE 4: Header summary counts are now color-coded
#   to match their tile colors for at-a-glance
#   readability on a NOC TV display.
# =====================================================

function Write-Dashboard {

    # Force default colors every refresh.
    try {
        $Host.UI.RawUI.BackgroundColor = $DefaultBackgroundColor
        $Host.UI.RawUI.ForegroundColor = $DefaultForegroundColor
    }
    catch {}

    Clear-Host

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $upCount       = ($NodeState.Values | Where-Object { $_.Status -eq "UP"       }).Count
    $warningCount  = ($NodeState.Values | Where-Object { $_.Status -eq "WARNING"  }).Count
    $degradedCount = ($NodeState.Values | Where-Object { $_.Status -eq "DEGRADED" }).Count
    $downCount     = ($NodeState.Values | Where-Object { $_.Status -eq "DOWN"     }).Count
    $initCount     = ($NodeState.Values | Where-Object { $_.Status -eq "INIT"     }).Count

    Write-Host "NOC SINGLE PANE TV DASHBOARD" `
        -ForegroundColor Cyan `
        -BackgroundColor $DefaultBackgroundColor

    # Static portions of the header line
    Write-Host "Last Refresh: $now | Total: $($Nodes.Count) | " `
        -ForegroundColor $DefaultForegroundColor `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host "UP: $upCount" `
        -ForegroundColor Green `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host "WARNING: $warningCount" `
        -ForegroundColor Yellow `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host "DEGRADED: $degradedCount" `
        -ForegroundColor Magenta `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host "DOWN: $downCount" `
        -ForegroundColor Red `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline

    Write-Host "INIT: $initCount" `
        -ForegroundColor Cyan `
        -BackgroundColor $DefaultBackgroundColor

    Write-Host "" -BackgroundColor $DefaultBackgroundColor

    $TopBorder = "+" + ("-" * ($TileWidth - 2)) + "+"
    $BottomBorder = $TopBorder

    for ($row = 0; $row -lt $Rows; $row++) {

        $rowNodes = @()

        for ($col = 0; $col -lt $Columns; $col++) {
            $index = ($row * $Columns) + $col

            if ($index -lt $Nodes.Count) {
                $rowNodes += $Nodes[$index]
            }
        }

        # Top border row
        foreach ($node in $rowNodes) {
            $state = $NodeState[$node.ID]
            $tileBgColor = Get-SafeBgColor -Status $state.Status

            Write-Host $TopBorder `
                -ForegroundColor White `
                -BackgroundColor $tileBgColor `
                -NoNewline

            Write-TileGap
        }

        Write-Host "" -BackgroundColor $DefaultBackgroundColor

        # Each tile has 9 content lines
        for ($lineIndex = 0; $lineIndex -lt 9; $lineIndex++) {

            foreach ($node in $rowNodes) {
                $state = $NodeState[$node.ID]
                $tileBgColor = Get-SafeBgColor -Status $state.Status

                $tileLines = Get-NodeTileLines -Node $node
                $text = Format-TileLine $tileLines[$lineIndex]

                Write-Host $text `
                    -ForegroundColor White `
                    -BackgroundColor $tileBgColor `
                    -NoNewline

                Write-TileGap
            }

            Write-Host "" -BackgroundColor $DefaultBackgroundColor
        }

        # Bottom border row
        foreach ($node in $rowNodes) {
            $state = $NodeState[$node.ID]
            $tileBgColor = Get-SafeBgColor -Status $state.Status

            Write-Host $BottomBorder `
                -ForegroundColor White `
                -BackgroundColor $tileBgColor `
                -NoNewline

            Write-TileGap
        }

        Write-Host "" -BackgroundColor $DefaultBackgroundColor
        Write-Host "" -BackgroundColor $DefaultBackgroundColor
    }

    Write-Host "Press CTRL + C to stop monitoring." `
        -ForegroundColor DarkGray `
        -BackgroundColor $DefaultBackgroundColor
}

# =====================================================
# MAIN LOOP
# =====================================================

while ($true) {

    foreach ($node in $Nodes) {
        Update-NodeState -Node $node
    }

    Write-Dashboard

    Start-Sleep -Seconds $RefreshIntervalSeconds
}

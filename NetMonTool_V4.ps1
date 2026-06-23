# =====================================================================
# NOCMonitor-TV.ps1
# NOC SINGLE PANE TV DASHBOARD + PERFORMANCE REPORTING
# =====================================================================
# Purpose:
#   Real-time single-window network health dashboard for 15 nodes,
#   laid out 5 columns x 3 rows for a NOC TV display, with daily and
#   weekly (Tuesday-to-Monday) performance reporting.
#
#   Reporting goes to TWO destinations that can be enabled together:
#     1. CSV FILES on a folder/share drive you choose (daily, weekly,
#        and an events incident-timeline file). No admin needed.
#     2. The WINDOWS EVENT LOG, so node up/down/degraded events show
#        up in Event Viewer (Applications and Services Logs).
#   Turn either or both on in the REPORT DESTINATION CONFIGURATION
#   section just below.
#
#   TIME STANDARD:
#   All report dates, week boundaries, and timestamps use ZULU (UTC)
#   time by default, so a daily report covers 00:00:00Z..23:59:59Z and
#   a weekly report covers Tuesday 00:00:00Z through Monday 23:59:59Z.
#   Set $UseZuluTime = $false to use the computer's local time instead.
#
# Target path (current location on this computer):
#   C:\Users\jariasp\Desktop\NOCMonitorTV_V5(no IPS reporting).ps1
#
# Run command:
#   powershell.exe -NoExit -ExecutionPolicy Bypass -File "C:\Users\jariasp\Desktop\NOCMonitorTV_V5(no IPS reporting).ps1"
#
# Requirements:
#   - Windows PowerShell 5.1 (no external modules)
#   - CSV files need no admin. The Event Log destination needs the
#     FIRST run to be "Run as Administrator" so the custom log can be
#     created; after that any user can run it.
#
# Background fix:
#   Forces the default console background to black and prevents
#   white-on-white display issues. DarkYellow is intentionally NOT
#   used anywhere because it renders as white/unreadable on some
#   computers.
# =====================================================================


# #####################################################################
#                                                                     #
#   REPORT DESTINATION CONFIGURATION   <===  EDIT THIS SECTION        #
#                                                                     #
# #####################################################################
#
# ---- TAB 1 : TIME STANDARD -----------------------------------------
#   $UseZuluTime = $true   All report dates/times use UTC (Zulu). A
#                          day is 00:00:00Z..23:59:59Z; a week is
#                          Tuesday 00:00Z .. Monday 23:59Z. RECOMMENDED
#                          for secured/CSfC environments.
#   $UseZuluTime = $false  Use the computer's local time instead.
#
# ---- TAB 2 : FILE REPORTS (CSV, can live on a SHARE DRIVE) ---------
#   $EnableFileReports = $true   Write daily, weekly, and events CSV
#                                files. Needs NO admin rights.
#   $ReportBasePath              WHERE those CSV files are created.
#                                Use a SHARE DRIVE for leadership
#                                access. Accepts:
#                                  - UNC share:  \\server\share\NOC\reports
#                                  - Mapped drive: H:\NOC\reports
#                                  - Local disk:   C:\NOC\reports
#                                The folder and its daily\, weekly\,
#                                events\ subfolders are created
#                                automatically. Leave "" to use a
#                                "reports" folder next to this script
#                                (currently: P:\3_tools\Network Monitor\reports).
#                                Examples:
#                                  ""  -> P:\3_tools\Network Monitor\reports
#                                  "P:\3_tools\Network Monitor\reports"
#                                  "\\server\share\NOC\reports"
#
# ---- TAB 3 : WINDOWS EVENT LOG (events in Event Viewer) -----------
#   $EnableEventLog = $true   Write node status-change events (and
#                             daily/weekly summaries) to the Windows
#                             Event Log so they appear in Event Viewer
#                             under Applications and Services Logs >
#                             NOCMonitor. FIRST run must be
#                             "Run as Administrator" to create the log.
#
# ---- TAB 4 : LIVE LATENCY LINE CHART (pop-up graph window) --------
#   $EnableLiveChart = $true  Open a graphical line chart alongside
#                             the console dashboard. X axis = the last
#                             10 ping results; Y axis = 0..2500 ms; one
#                             colored line per node with a legend. It
#                             is fed by the SAME pings the dashboard
#                             already does (no extra pinging) and
#                             refreshes every 2 seconds. Set $false to
#                             run console-only (e.g., headless hosts).
#
$UseZuluTime       = $true
$EnableFileReports = $true
$ReportBasePath    = ""
$EnableEventLog    = $true
$EnableLiveChart   = $true
#
# #####################################################################


# =====================================================================
# CONFIGURATION - NODE LIST
# Replace these placeholder IPs with your real destination IPs.
# Add/remove nodes here; the dashboard and reports adjust automatically.
# =====================================================================

$Nodes = @(
    @{ ID = 1;  NodeName = "NODE_1";  IP = "8.8.8.8"  },
    @{ ID = 2;  NodeName = "NODE_2";  IP = "8.8.8.8"  },
    @{ ID = 3;  NodeName = "NODE_3";  IP = "8.8.8.8" },
    @{ ID = 4;  NodeName = "NODE_4";  IP = "8.8.8.8" },
    @{ ID = 5;  NodeName = "NODE_5";  IP = "8.8.8.8" },
    @{ ID = 6;  NodeName = "NODE_6";  IP = "8.8.8.8" },
    @{ ID = 7;  NodeName = "NODE_7";  IP = "8.8.8.8" },
    @{ ID = 8;  NodeName = "NODE_8";  IP = "8.8.8.8" },
    @{ ID = 9;  NodeName = "NODE_9";  IP = "8.8.8.8" },
    @{ ID = 10; NodeName = "NODE_10"; IP = "8.8.8.8" },
    @{ ID = 11; NodeName = "NODE_11"; IP = "8.8.8.8" },
    @{ ID = 12; NodeName = "NODE_12"; IP = "8.8.8.8" },
    @{ ID = 13; NodeName = "NODE_13"; IP = "8.8.8.8" },
    @{ ID = 14; NodeName = "NODE_14"; IP = "8.8.8.8" },
    @{ ID = 15; NodeName = "NODE_15"; IP = "8.8.8.8" }
)

# =====================================================================
# UPDATE TIMING NOTE - HOW THE 5-SECOND REFRESH WORKS
# =====================================================================
# This dashboard uses PARALLEL polling. Every cycle it fires an
# asynchronous ping to ALL nodes at once (.NET SendPingAsync) and then
# waits for them together, so the time spent pinging is about the
# LONGEST single ping - not the SUM of every ping.
#
#   - All 15 nodes healthy: pings finish in tens of milliseconds.
#   - Some nodes timing out: those still finish at $PingTimeoutMs
#     (2500ms) because each async ping self-times-out, and they all
#     run at the same time. Even if ALL 15 time out, the wait is about
#     5.5 seconds total, NOT 15 x 5.5 seconds.
#
# After pinging + drawing + reporting, the loop sleeps only the time
# LEFT in the interval, so the cycle targets a true cadence of:
#
#   $RefreshIntervalSeconds  (default 5 seconds)
#
# If a cycle's work somehow runs longer than the interval (e.g., many
# simultaneous timeouts), that cycle simply does not sleep and the
# next one starts immediately - the dashboard never falls behind by
# the SUM of timeouts the way sequential polling did.
#
# Anything over $PingTimeoutMs (2500ms) is treated as timeout/failure.
# =====================================================================

# =====================================================================
# MONITORING THRESHOLDS
# =====================================================================

$FailThreshold        = 3      # Consecutive failures before DOWN
$LatencyThresholdMs   = 500    # AVG10 above this = DEGRADED
$LossThresholdPercent = 20     # LOSS10 above this = DEGRADED
$PingTimeoutMs        = 1500   # Replies slower than this count as failure
$RefreshIntervalSeconds = 5    # Sleep between polling cycles (see timing note)
$HistoryLimit         = 10     # Attempts kept for AVG10 / LOSS10 / JITTER

# Jitter is displayed for visibility and baseline collection only.
# It does NOT affect tile color/status because we do not have a jitter
# baseline yet. Once normal behavior is understood, a threshold like
# the one below can be added into the DEGRADED logic.
# $JitterThresholdMs = 50

# =====================================================================
# DASHBOARD LAYOUT - NOC TV SETTINGS
# =====================================================================

$Columns  = 5
$Rows     = 3

# Tile width includes the border characters.
$TileWidth = 34

# Spacing between node boxes (always drawn with a black background).
$TileGap = "    "

# Console size for a wide TV display.
# Width needed: 5 tiles * 34 chars = 170, plus 4 gaps * 4 chars = 16,
# so around 186+. We use 200 for headroom.
$ConsoleWidth  = 200
$ConsoleHeight = 45

# Default dashboard colors. Black background + white text avoids the
# white-on-white problem seen with terminal default color schemes.
$DefaultBackgroundColor = "Black"
$DefaultForegroundColor = "White"

# =====================================================================
# TIME HELPERS (Zulu/UTC vs local)
# =====================================================================
# Every reporting date, week boundary, and timestamp flows through
# these, so flipping $UseZuluTime switches the whole script between
# UTC and local time consistently.
# =====================================================================

function Get-Now {
    if ($UseZuluTime) { return [DateTime]::UtcNow }
    else              { return (Get-Date) }
}

function Get-NowStamp  { return (Get-Now).ToString("yyyy-MM-dd HH:mm:ss") }
function Get-TodayStamp { return (Get-Now).ToString("yyyy-MM-dd") }

# Label shown next to times on the dashboard so the operator knows the
# standard at a glance.
if ($UseZuluTime) { $TimeLabel = "Z" } else { $TimeLabel = "local" }

# =====================================================================
# RESOLVE SCRIPT ROOT + REPORT FOLDERS
# =====================================================================
# $PSScriptRoot can be empty if the code is pasted into a console,
# so fall back to the current directory.
if ($PSScriptRoot) { $ScriptRoot = $PSScriptRoot }
else               { $ScriptRoot = (Get-Location).Path }

# If the operator left $ReportBasePath empty, default to a "reports"
# folder next to the script.
if ([string]::IsNullOrWhiteSpace($ReportBasePath)) {
    $ReportBasePath = Join-Path $ScriptRoot "reports"
}

# File-mode subfolders.
$DailyReportDir  = Join-Path $ReportBasePath "daily"
$WeeklyReportDir = Join-Path $ReportBasePath "weekly"
$EventsReportDir = Join-Path $ReportBasePath "events"

# =====================================================================
# EVENT LOG SETTINGS (only used when $EnableEventLog = $true)
# =====================================================================
# Event ID reference (filter on these in Event Viewer):
#   1001 Information  Node recovered / came UP
#   2001 Warning      Node entered WARNING
#   2002 Warning      Node entered DEGRADED
#   3001 Error        Node went DOWN
#   4000 Information  Daily counters snapshot (per node)
#   4001 Information  Daily FINAL summary (per node, at rollover)
#   5001 Information  Weekly summary (per node, end of Tue-Mon week)
# =====================================================================

$EventLogName = "NOCMonitor"
$EventSource  = "NOCMonitor-TV"
$EventLogMaxSize = 64MB

$EventIdNodeUp        = 1001
$EventIdNodeWarning   = 2001
$EventIdNodeDegraded  = 2002
$EventIdNodeDown      = 3001
$EventIdDailySnapshot = 4000
$EventIdDailyFinal    = 4001
$EventIdWeeklySummary = 5001

# The event log cannot absorb 15 entries every 2 seconds, so its
# counter snapshots are throttled to this interval. CSV files are
# cheap and are rewritten every cycle instead.
$SnapshotIntervalMinutes = 5

# =====================================================================
# LIVE CHART SETTINGS (only used when $EnableLiveChart = $true)
# =====================================================================
# One distinct line color per node, matched to the legend. Edit freely
# (any .NET / HTML color name works).
$NodeColors = @{
    1="Red"; 2="Blue"; 3="Green"; 4="Orange"; 5="Purple";
    6="Brown"; 7="DarkCyan"; 8="DarkMagenta"; 9="Gold"; 10="DarkGreen";
    11="DarkBlue"; 12="DarkRed"; 13="Teal"; 14="DarkOrange"; 15="DarkViolet"
}

# Y-axis range for the chart, in milliseconds.
$ChartYMin = 0
$ChartYMax = 2500

# Value plotted when a ping TIMES OUT / drops. Default is the ceiling
# ($ChartYMax) so an outage SPIKES to the top of the chart and is
# obvious on a NOC screen. Set to 0 if you would rather a drop fall to
# the bottom of the chart instead.
$ChartTimeoutValue = $ChartYMax

# How many recent results the chart shows on the X axis.
$ChartHistoryLimit = 10

# =====================================================================
# REPORTING RUNTIME STATE
# =====================================================================
# Independent readiness flags - both destinations can be active.
$script:FileReady     = $false
$script:EventLogReady = $false

# Short status strings shown in the dashboard header.
$script:FileTargetText     = ""
$script:EventLogTargetText = ""

# The report-day the daily counters currently belong to (Zulu date if
# $UseZuluTime).
$script:CurrentReportDate = Get-TodayStamp

# When the last EventLog-mode snapshot was written.
$script:LastSnapshotTime = Get-Now

# Live chart plumbing (set by Start-LiveChart when $EnableLiveChart).
$script:ChartSync     = $null   # synchronized hashtable shared with GUI
$script:ChartRunspace = $null
$script:ChartPs       = $null
$script:ChartHandle   = $null

# =====================================================================
# FUNCTION: Get-WeekStart
# Returns the TUESDAY that starts the report week containing the
# given date. Report weeks are hardcoded as Tuesday-to-Monday:
# Tuesday is day 1 and the following Monday is day 7. With Zulu time
# this is Tuesday 00:00:00Z through Monday 23:59:59Z.
#
# .NET DayOfWeek numbering: Sunday=0, Monday=1, Tuesday=2 ... Sat=6.
# The (+5 % 7) math converts that so Tuesday=0 days back, Wednesday=1
# day back, ... and Monday=6 days back (Monday closes out the week
# that began the PREVIOUS Tuesday).
# =====================================================================

function Get-WeekStart {
    param ([datetime]$Date)
    $daysSinceTuesday = ([int]$Date.DayOfWeek + 5) % 7
    return $Date.Date.AddDays(-$daysSinceTuesday)
}

function Get-DailyReportFilePath {
    param ([string]$ReportDate)
    return (Join-Path $DailyReportDir "noc_daily_$ReportDate.csv")
}

function Get-WeeklyReportFilePath {
    param ([datetime]$WeekStart)
    # Filename date is the Tuesday the week starts on.
    return (Join-Path $WeeklyReportDir ("noc_weekly_" + $WeekStart.ToString("yyyy-MM-dd") + ".csv"))
}

function Get-EventsReportFilePath {
    param ([string]$ReportDate)
    return (Join-Path $EventsReportDir "noc_events_$ReportDate.csv")
}

# =====================================================================
# INITIAL CONSOLE SETUP
# =====================================================================

$Host.UI.RawUI.WindowTitle = "NOC SINGLE PANE TV DASHBOARD"

try {
    $raw = $Host.UI.RawUI

    # Force default console colors so the dashboard starts readable.
    $raw.BackgroundColor = $DefaultBackgroundColor
    $raw.ForegroundColor = $DefaultForegroundColor

    $bufferSize = $raw.BufferSize
    $windowSize = $raw.WindowSize

    # Buffer must be at least as large as the window.
    $bufferSize.Width  = $ConsoleWidth
    $bufferSize.Height = 500

    $windowSize.Width  = $ConsoleWidth
    $windowSize.Height = $ConsoleHeight

    $raw.BufferSize = $bufferSize
    $raw.WindowSize = $windowSize

    Clear-Host
}
catch {
    # Console resizing can fail depending on the terminal/host.
    # That is OK - do not crash; monitoring continues at whatever
    # size the window currently is.
}

# =====================================================================
# PER-NODE STATE
# =====================================================================
# $NodeState  - short-term health used for the live dashboard
#               (last 10 attempts only).
# $DailyStats - cumulative counters for the CURRENT report day,
#               written out to the chosen report destination(s).
# =====================================================================

$NodeState  = @{}
$DailyStats = @{}

foreach ($node in $Nodes) {
    $NodeState[$node.ID] = @{
        LatencyHistory     = @()      # Successful latencies (ms), last 10
        PingHistory        = @()      # $true/$false per attempt, last 10
        ChartHistory       = @()      # Per-attempt ms for the line chart,
                                      # last 10; a drop = $ChartTimeoutValue
        ConsecutiveFails   = 0
        LastSuccessfulPing = "N/A"
        CurrentLatency     = $null
        AvgLatency         = "N/A"
        LossPercent        = 0
        Jitter             = "N/A"
        Status             = "INIT"   # INIT until the first check completes
    }

    $DailyStats[$node.ID] = @{
        TotalAttempts      = 0
        SuccessfulAttempts = 0
        FailedAttempts     = 0
        LatencySumMs       = 0        # Sum of successful latencies (ms)
        LatencySamples     = 0        # Count of successful latencies
    }
}

# =====================================================================
# FUNCTION: Get-NodeDailyRow
# Builds the per-node daily reporting record from current counters.
# Shared by both File and Event Log destinations.
# =====================================================================

function Get-NodeDailyRow {
    param (
        [hashtable]$Node,
        [string]$ReportDate,
        [string]$ExportTime
    )

    $daily = $DailyStats[$Node.ID]

    if ($daily.TotalAttempts -gt 0) {
        $dropPercent  = [math]::Round(($daily.FailedAttempts / $daily.TotalAttempts) * 100, 2)
        $availPercent = [math]::Round(($daily.SuccessfulAttempts / $daily.TotalAttempts) * 100, 2)
    }
    else {
        $dropPercent  = 0
        $availPercent = 0
    }

    if ($daily.LatencySamples -gt 0) {
        $avgLatency = [math]::Round($daily.LatencySumMs / $daily.LatencySamples, 1)
    }
    else {
        $avgLatency = 0
    }

    # LatencySumMs and LatencySamples are carried so the weekly report
    # can compute a correctly WEIGHTED average latency.
    return [PSCustomObject]@{
        ExportTime          = $ExportTime
        ReportDate          = $ReportDate
        NodeName            = $Node.NodeName
        TotalAttempts       = $daily.TotalAttempts
        SuccessfulAttempts  = $daily.SuccessfulAttempts
        FailedAttempts      = $daily.FailedAttempts
        DropPercent         = $dropPercent
        AvailabilityPercent = $availPercent
        AvgLatencyMs        = $avgLatency
        LatencySumMs        = $daily.LatencySumMs
        LatencySamples      = $daily.LatencySamples
    }
}

# =====================================================================
# SHARED AGGREGATION HELPERS (used by both destinations)
# =====================================================================

# Sums raw daily counters. Accepts either CSV PSCustomObjects (File)
# or parsed Key=Value hashtables (Event Log); member access works on
# both shapes in PowerShell.
function Get-WeightedTotals {
    param ($DailyRecords)

    $t = 0; $s = 0; $f = 0; $latSum = 0.0; $latSamples = 0
    foreach ($rec in $DailyRecords) {
        try {
            $t          += [int]$rec.TotalAttempts
            $s          += [int]$rec.SuccessfulAttempts
            $f          += [int]$rec.FailedAttempts
            $latSum     += [double]$rec.LatencySumMs
            $latSamples += [int]$rec.LatencySamples
        }
        catch {}
    }
    return @{ Total = $t; Success = $s; Failed = $f; LatSum = $latSum; LatSamples = $latSamples }
}

function New-WeeklyRow {
    param (
        [hashtable]$Node,
        [string]$ExportTime,
        [datetime]$WeekStart,
        [datetime]$WeekEnd,
        [hashtable]$Totals
    )

    if ($Totals.Total -gt 0) {
        $dropPercent  = [math]::Round(($Totals.Failed / $Totals.Total) * 100, 2)
        $availPercent = [math]::Round(($Totals.Success / $Totals.Total) * 100, 2)
    }
    else {
        $dropPercent = 0; $availPercent = 0
    }

    if ($Totals.LatSamples -gt 0) {
        $avgLatency = [math]::Round($Totals.LatSum / $Totals.LatSamples, 1)
    }
    else {
        $avgLatency = 0
    }

    return [PSCustomObject]@{
        ExportTime          = $ExportTime
        WeekStart           = $WeekStart.ToString("yyyy-MM-dd")
        WeekEnd             = $WeekEnd.ToString("yyyy-MM-dd")
        NodeName            = $Node.NodeName
        TotalAttempts       = $Totals.Total
        SuccessfulAttempts  = $Totals.Success
        FailedAttempts      = $Totals.Failed
        DropPercent         = $dropPercent
        AvailabilityPercent = $availPercent
        AvgLatencyMs        = $avgLatency
    }
}

# Loads saved counters into a node from a CSV object or Key=Value
# hashtable.
function Set-NodeCountersFromRecord {
    param ([int]$NodeId, $Record)
    try {
        $DailyStats[$NodeId] = @{
            TotalAttempts      = [int]$Record.TotalAttempts
            SuccessfulAttempts = [int]$Record.SuccessfulAttempts
            FailedAttempts     = [int]$Record.FailedAttempts
            LatencySumMs       = [double]$Record.LatencySumMs
            LatencySamples     = [int]$Record.LatencySamples
        }
    }
    catch {}
}

# =====================================================================
# =====================================================================
#   REPORTING - FILE DESTINATION (CSV, share-drive friendly)
# =====================================================================
# =====================================================================

# ---------------------------------------------------------------------
# Initialize-FileReporting
# Creates the report folders (works for local, mapped-drive, or UNC
# share paths) and verifies the location is writable by touching a
# temp file, so an unreachable share fails cleanly at startup instead
# of silently losing data later.
# ---------------------------------------------------------------------
function Initialize-FileReporting {
    try {
        foreach ($dir in @($ReportBasePath, $DailyReportDir, $WeeklyReportDir, $EventsReportDir)) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
            }
        }

        $probe = Join-Path $ReportBasePath ".write_test.tmp"
        "ok" | Out-File -FilePath $probe -Force -ErrorAction Stop
        Remove-Item $probe -Force -ErrorAction SilentlyContinue

        $script:FileReady      = $true
        $script:FileTargetText = $ReportBasePath
    }
    catch {
        $script:FileReady      = $false
        $script:FileTargetText = "UNAVAILABLE (cannot write to $ReportBasePath)"
    }
}

# ---------------------------------------------------------------------
# Save-DailyReport_File
# Writes the day-so-far counters to noc_daily_DATE.csv (one row per
# node). Rewritten every cycle so a crash never loses the current day.
# ---------------------------------------------------------------------
function Save-DailyReport_File {
    param ([string]$ReportDate = $script:CurrentReportDate)

    if (-not $script:FileReady) { return }

    $exportTime = Get-NowStamp
    $rows = foreach ($node in $Nodes) {
        Get-NodeDailyRow -Node $node -ReportDate $ReportDate -ExportTime $exportTime
    }

    try {
        $rows | Export-Csv -Path (Get-DailyReportFilePath -ReportDate $ReportDate) -NoTypeInformation -Force
    }
    catch {
        # File locked (open in Excel) or share briefly gone. Skip; the
        # next cycle tries again. Never crash the dashboard.
    }
}

# ---------------------------------------------------------------------
# Get-WeeklyRowsFromFiles
# Reads the Tuesday-to-Monday week's daily CSVs and returns weighted
# per-node weekly rows.
# ---------------------------------------------------------------------
function Get-WeeklyRowsFromFiles {
    param ([datetime]$WeekStart, [datetime]$WeekEnd)

    try {
        $dailyFiles = Get-ChildItem -Path $DailyReportDir -Filter "noc_daily_*.csv" -ErrorAction Stop
    }
    catch { return @() }

    $dailyRows = @()
    foreach ($file in $dailyFiles) {
        if ($file.BaseName -match "noc_daily_(\d{4}-\d{2}-\d{2})$") {
            try { $fileDate = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd", $null) }
            catch { continue }

            if ($fileDate.Date -ge $WeekStart.Date -and $fileDate.Date -le $WeekEnd.Date) {
                try { $dailyRows += Import-Csv -Path $file.FullName } catch {}
            }
        }
    }

    if ($dailyRows.Count -eq 0) { return @() }

    $exportTime = Get-NowStamp
    $weeklyRows = foreach ($node in $Nodes) {
        $nodeRows = $dailyRows | Where-Object { $_.NodeName -eq $node.NodeName }
        if (-not $nodeRows) { continue }
        $sums = Get-WeightedTotals -DailyRecords $nodeRows
        New-WeeklyRow -Node $node -ExportTime $exportTime -WeekStart $WeekStart -WeekEnd $WeekEnd -Totals $sums
    }
    return $weeklyRows
}

# ---------------------------------------------------------------------
# Save-WeeklyReport_File
# Writes pre-computed weekly rows to noc_weekly_TUESDAY.csv.
# ---------------------------------------------------------------------
function Save-WeeklyReport_File {
    param ($WeeklyRows, [datetime]$WeekStart)

    if (-not $script:FileReady) { return }
    if (-not $WeeklyRows -or @($WeeklyRows).Count -eq 0) { return }

    try {
        $WeeklyRows | Export-Csv -Path (Get-WeeklyReportFilePath -WeekStart $WeekStart) -NoTypeInformation -Force
    }
    catch {}
}

# ---------------------------------------------------------------------
# Write-StatusChange_File
# Appends one row to noc_events_DATE.csv so the file destination has a
# clean, openable incident timeline (the CSV equivalent of the Event
# Viewer list).
# ---------------------------------------------------------------------
function Write-StatusChange_File {
    param ([hashtable]$Node, [string]$OldStatus, [string]$NewStatus, [string]$Level)

    if (-not $script:FileReady) { return }

    $state = $NodeState[$Node.ID]
    $row = [PSCustomObject]@{
        Time               = Get-NowStamp
        TimeStandard       = $TimeLabel
        Level              = $Level
        NodeName           = $Node.NodeName
        OldStatus          = $OldStatus
        NewStatus          = $NewStatus
        ConsecutiveFails   = $state.ConsecutiveFails
        Avg10LatencyMs     = $state.AvgLatency
        Loss10Percent      = $state.LossPercent
        LastSuccessfulPing = $state.LastSuccessfulPing
    }

    try {
        $file = Get-EventsReportFilePath -ReportDate $script:CurrentReportDate
        if (-not (Test-Path $file)) {
            $row | Export-Csv -Path $file -NoTypeInformation -Force
        }
        else {
            $row | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content -Path $file
        }
    }
    catch {}
}

# ---------------------------------------------------------------------
# Load-TodayCounters_File
# Reloads today's counters from today's daily CSV so a mid-day restart
# does not reset leadership numbers to zero.
# ---------------------------------------------------------------------
function Load-TodayCounters_File {
    if (-not $script:FileReady) { return }

    $file = Get-DailyReportFilePath -ReportDate $script:CurrentReportDate
    if (-not (Test-Path $file)) { return }

    try { $savedRows = Import-Csv -Path $file } catch { return }

    foreach ($node in $Nodes) {
        $saved = $savedRows | Where-Object { $_.NodeName -eq $node.NodeName } | Select-Object -First 1
        if ($null -ne $saved) { Set-NodeCountersFromRecord -NodeId $node.ID -Record $saved }
    }
}

# =====================================================================
# =====================================================================
#   REPORTING - EVENT LOG DESTINATION (Event Viewer)
# =====================================================================
# =====================================================================

# ---------------------------------------------------------------------
# Initialize-EventLogReporting
# Creates the custom log + source (needs admin ONCE). On failure
# (usually: not run as admin) the event destination is disabled but
# monitoring + file reporting continue, and the header shows how to
# fix it.
# ---------------------------------------------------------------------
function Initialize-EventLogReporting {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName $EventLogName -Source $EventSource -ErrorAction Stop
            Limit-EventLog -LogName $EventLogName `
                -MaximumSize $EventLogMaxSize `
                -OverflowAction OverwriteAsNeeded `
                -ErrorAction SilentlyContinue
        }
        $script:EventLogReady      = $true
        $script:EventLogTargetText = "$EventLogName (Event Viewer > Applications and Services Logs)"
    }
    catch {
        $script:EventLogReady      = $false
        $script:EventLogTargetText = "UNAVAILABLE - run once as Administrator to create '$EventLogName'"
    }
}

function Write-NocEvent {
    param ([int]$EventId, [string]$EntryType, [string]$Message)
    if (-not $script:EventLogReady) { return }
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource `
            -EventId $EventId -EntryType $EntryType -Message $Message
    }
    catch {}
}

# Snapshot/summary events store data as Key=Value lines for clean
# Event Viewer display AND machine parsing on reload.
function ConvertFrom-NocEventMessage {
    param ([string]$Message)
    $data = @{}
    foreach ($line in ($Message -split "[\r\n]+")) {
        $pair = $line -split "=", 2
        if ($pair.Count -eq 2) { $data[$pair[0].Trim()] = $pair[1].Trim() }
    }
    return $data
}

function Write-StatusChange_EventLog {
    param ([hashtable]$Node, [string]$OldStatus, [string]$NewStatus, [string]$Level)

    switch ($NewStatus) {
        "DOWN"     { $eventId = $EventIdNodeDown     }
        "DEGRADED" { $eventId = $EventIdNodeDegraded }
        "WARNING"  { $eventId = $EventIdNodeWarning  }
        "UP"       { $eventId = $EventIdNodeUp       }
        default    { return }
    }

    $state = $NodeState[$Node.ID]
    # The event's own TimeGenerated is the machine local time (Windows
    # sets that); the body carries the Zulu detail so both are visible.
    $message = @(
        "$($Node.NodeName) ($($Node.IP)) status changed: $OldStatus -> $NewStatus",
        "",
        "EventTime$TimeLabel=$(Get-NowStamp)",
        "ConsecutiveFails=$($state.ConsecutiveFails)",
        "Avg10LatencyMs=$($state.AvgLatency)",
        "Loss10Percent=$($state.LossPercent)",
        "LastSuccessfulPing=$($state.LastSuccessfulPing)"
    ) -join "`r`n"

    Write-NocEvent -EventId $eventId -EntryType $Level -Message $message
}

function Save-DailyReport_EventLog {
    param ([string]$ReportDate = $script:CurrentReportDate, [switch]$Final)

    if (-not $script:EventLogReady) { return }

    if ($Final) { $header = "NOC_DAILY_FINAL";    $eventId = $EventIdDailyFinal }
    else        { $header = "NOC_DAILY_SNAPSHOT"; $eventId = $EventIdDailySnapshot }

    $exportTime = Get-NowStamp
    foreach ($node in $Nodes) {
        $r = Get-NodeDailyRow -Node $node -ReportDate $ReportDate -ExportTime $exportTime
        $message = @(
            $header,
            "ReportDate=$($r.ReportDate)",
            "NodeName=$($r.NodeName)",
            "TotalAttempts=$($r.TotalAttempts)",
            "SuccessfulAttempts=$($r.SuccessfulAttempts)",
            "FailedAttempts=$($r.FailedAttempts)",
            "DropPercent=$($r.DropPercent)",
            "AvailabilityPercent=$($r.AvailabilityPercent)",
            "AvgLatencyMs=$($r.AvgLatencyMs)",
            "LatencySumMs=$($r.LatencySumMs)",
            "LatencySamples=$($r.LatencySamples)"
        ) -join "`r`n"
        Write-NocEvent -EventId $eventId -EntryType "Information" -Message $message
    }
}

# Reads 4000/4001 daily events for the week and returns weighted
# per-node weekly rows. Used only when files are NOT the source.
function Get-WeeklyRowsFromEventLog {
    param ([datetime]$WeekStart, [datetime]$WeekEnd)

    try {
        # Pad the TimeGenerated query window by a day on each side to
        # absorb any UTC/local skew; the ReportDate string in the body
        # does the precise day filtering below.
        $rawEvents = Get-EventLog -LogName $EventLogName -Source $EventSource `
            -After $WeekStart.AddDays(-1) -Before $WeekEnd.AddDays(2) -ErrorAction Stop
    }
    catch { return @() }

    # Latest counters per (node, day). Get-EventLog is newest-first, so
    # the first event seen for a key wins.
    $latestPerNodeDay = @{}
    foreach ($evt in $rawEvents) {
        if ($evt.EventID -ne $EventIdDailySnapshot -and $evt.EventID -ne $EventIdDailyFinal) { continue }
        $data = ConvertFrom-NocEventMessage -Message $evt.Message
        if (-not $data.ContainsKey("ReportDate") -or -not $data.ContainsKey("NodeName")) { continue }

        try { $reportDay = [datetime]::ParseExact($data["ReportDate"], "yyyy-MM-dd", $null) }
        catch { continue }
        if ($reportDay -lt $WeekStart -or $reportDay -gt $WeekEnd) { continue }

        $key = "$($data["NodeName"])|$($data["ReportDate"])"
        if (-not $latestPerNodeDay.ContainsKey($key)) { $latestPerNodeDay[$key] = $data }
    }

    if ($latestPerNodeDay.Count -eq 0) { return @() }

    $exportTime = Get-NowStamp
    $weeklyRows = foreach ($node in $Nodes) {
        $nodeDays = $latestPerNodeDay.Values | Where-Object { $_["NodeName"] -eq $node.NodeName }
        if (-not $nodeDays) { continue }
        $sums = Get-WeightedTotals -DailyRecords $nodeDays
        New-WeeklyRow -Node $node -ExportTime $exportTime -WeekStart $WeekStart -WeekEnd $WeekEnd -Totals $sums
    }
    return $weeklyRows
}

function Save-WeeklyReport_EventLog {
    param ($WeeklyRows)

    if (-not $script:EventLogReady) { return }
    if (-not $WeeklyRows -or @($WeeklyRows).Count -eq 0) { return }

    foreach ($row in $WeeklyRows) {
        $message = @(
            "NOC_WEEKLY_SUMMARY",
            "WeekStart=$($row.WeekStart)",
            "WeekEnd=$($row.WeekEnd)",
            "NodeName=$($row.NodeName)",
            "TotalAttempts=$($row.TotalAttempts)",
            "SuccessfulAttempts=$($row.SuccessfulAttempts)",
            "FailedAttempts=$($row.FailedAttempts)",
            "DropPercent=$($row.DropPercent)",
            "AvailabilityPercent=$($row.AvailabilityPercent)",
            "AvgLatencyMs=$($row.AvgLatencyMs)"
        ) -join "`r`n"
        Write-NocEvent -EventId $EventIdWeeklySummary -EntryType "Information" -Message $message
    }
}

function Load-TodayCounters_EventLog {
    if (-not $script:EventLogReady) { return }

    try {
        $rawEvents = Get-EventLog -LogName $EventLogName -Source $EventSource `
            -After (Get-Date).Date.AddDays(-1) -ErrorAction Stop
    }
    catch { return }

    $loaded = @{}
    foreach ($evt in $rawEvents) {
        if ($evt.EventID -ne $EventIdDailySnapshot -and $evt.EventID -ne $EventIdDailyFinal) { continue }
        $data = ConvertFrom-NocEventMessage -Message $evt.Message
        if ($data["ReportDate"] -ne $script:CurrentReportDate) { continue }
        $name = $data["NodeName"]
        if (-not $name -or $loaded.ContainsKey($name)) { continue }
        $loaded[$name] = $data
    }

    foreach ($node in $Nodes) {
        if ($loaded.ContainsKey($node.NodeName)) {
            Set-NodeCountersFromRecord -NodeId $node.ID -Record $loaded[$node.NodeName]
        }
    }
}

# =====================================================================
# REPORTING DISPATCHERS
# These are what the rest of the script calls. Each one fans out to
# every ENABLED destination, so File and Event Log can both be active.
# =====================================================================

function Initialize-Reporting {
    if ($EnableFileReports) { Initialize-FileReporting }
    else { $script:FileReady = $false; $script:FileTargetText = "disabled" }

    if ($EnableEventLog) { Initialize-EventLogReporting }
    else { $script:EventLogReady = $false; $script:EventLogTargetText = "disabled" }
}

function Write-StatusChange {
    param ([hashtable]$Node, [string]$OldStatus, [string]$NewStatus, [string]$Level)
    if ($script:FileReady)     { Write-StatusChange_File     -Node $Node -OldStatus $OldStatus -NewStatus $NewStatus -Level $Level }
    if ($script:EventLogReady) { Write-StatusChange_EventLog -Node $Node -OldStatus $OldStatus -NewStatus $NewStatus -Level $Level }
}

# Writes the daily report to every enabled destination. -Final only
# affects the Event Log (it raises a NOC_DAILY_FINAL event); the file
# destination keeps one live CSV per day where the last write IS final.
function Save-DailyReport {
    param ([string]$ReportDate = $script:CurrentReportDate, [switch]$Final)
    if ($script:FileReady)     { Save-DailyReport_File     -ReportDate $ReportDate }
    if ($script:EventLogReady) { Save-DailyReport_EventLog -ReportDate $ReportDate -Final:$Final }
}

# Computes the weekly rollup ONCE (files preferred as the source of
# truth, else the event log) and writes it to every enabled
# destination.
function Save-WeeklyReport {
    param ([datetime]$ForDate = (Get-Now))

    $weekStart = Get-WeekStart -Date $ForDate
    $weekEnd   = $weekStart.AddDays(6)

    if ($script:FileReady) {
        $rows = Get-WeeklyRowsFromFiles -WeekStart $weekStart -WeekEnd $weekEnd
    }
    elseif ($script:EventLogReady) {
        $rows = Get-WeeklyRowsFromEventLog -WeekStart $weekStart -WeekEnd $weekEnd
    }
    else {
        return
    }

    Save-WeeklyReport_File     -WeeklyRows $rows -WeekStart $weekStart
    Save-WeeklyReport_EventLog -WeeklyRows $rows
}

# Reloads today's counters on startup. Files are the preferred source;
# fall back to the event log if files are off.
function Load-TodayCounters {
    if ($script:FileReady)          { Load-TodayCounters_File }
    elseif ($script:EventLogReady)  { Load-TodayCounters_EventLog }
}

# =====================================================================
# FUNCTION: Get-SafeBgColor
# Maps a status to a tile background that is always readable with
# white text. DarkYellow is never returned because it displays as
# white/unreadable on some computers.
# =====================================================================

function Get-SafeBgColor {
    param ([string]$Status)
    switch ($Status) {
        "UP"       { return "DarkGreen"   }
        "WARNING"  { return "DarkMagenta" }
        "DEGRADED" { return "DarkMagenta" }
        "DOWN"     { return "DarkRed"     }
        "INIT"     { return "DarkCyan"    }
        default    { return "Black"       }
    }
}

# =====================================================================
# FUNCTION: Get-SafeFgColor
# Always returns a foreground color that is readable on every
# background Get-SafeBgColor can produce.
# =====================================================================

function Get-SafeFgColor {
    param ([string]$Status)
    return "White"   # readable on all of the dark backgrounds above
}

# =====================================================================
# FUNCTION: Invoke-AllPings  (PARALLEL)
# Pings EVERY node at the same time using .NET SendPingAsync, then
# waits for them all together. Returns a hashtable keyed by node ID:
#     @{ <id> = @{ Success = $true/$false; Latency = <ms or $null> } }
#
# Why parallel: each async ping self-times-out at $TimeoutMs, and they
# all run concurrently, so the whole batch finishes in about the
# longest single ping (<= $TimeoutMs) instead of the SUM of all pings.
# That is what makes a true ~2-second refresh possible.
#
# Notes:
#   - One Ping object per node: a single Ping cannot run two async
#     sends at once, so each node gets its own (created and disposed
#     within this call).
#   - Any non-Success reply, timeout, or exception counts as failure.
# =====================================================================

function Invoke-AllPings {
    param ([array]$NodeList, [int]$TimeoutMs)

    # Start every ping; keep the Ping object + its Task together.
    $pending = @()
    foreach ($node in $NodeList) {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $task = $null
        try {
            $task = $ping.SendPingAsync($node.IP, $TimeoutMs)
        }
        catch {
            # Bad address/format - leave $task null; treated as failure.
        }
        $pending += [PSCustomObject]@{ Node = $node; Ping = $ping; Task = $task }
    }

    # Wait for all of them together. Each task self-times-out at
    # $TimeoutMs; the +2000ms cushion just covers scheduling overhead.
    $tasks = @($pending | Where-Object { $_.Task -ne $null } | ForEach-Object { $_.Task })
    if ($tasks.Count -gt 0) {
        try { [System.Threading.Tasks.Task]::WaitAll($tasks, $TimeoutMs + 2000) | Out-Null }
        catch {
            # WaitAll throws if any task faulted; each task is read
            # individually below, so this is safe to ignore.
        }
    }

    # Collect results.
    $results = @{}
    foreach ($item in $pending) {
        $success = $false
        $latency = $null
        try {
            if ($item.Task -ne $null -and
                $item.Task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $reply = $item.Task.Result
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $success = $true
                    $latency = [int]$reply.RoundtripTime
                }
            }
        }
        catch {
            $success = $false; $latency = $null
        }
        # Always release the Ping object.
        try { if ($item.Ping -ne $null) { $item.Ping.Dispose() } } catch {}

        $results[$item.Node.ID] = @{ Success = $success; Latency = $latency }
    }

    return $results
}

# =====================================================================
# FUNCTION: Update-NodeState
# Updates one node's live dashboard state + daily counters from a
# PingResult already produced by Invoke-AllPings (the parallel pinger).
# Status transitions are reported to every enabled destination as they
# happen.
#
#   $PingResult = @{ Success = $true/$false; Latency = <ms or $null> }
#
# Health status logic:
#   DOWN     - ConsecutiveFails >= FailThreshold (3)
#   WARNING  - ConsecutiveFails > 0 but < FailThreshold
#   DEGRADED - reachable, but AVG10 > LatencyThresholdMs OR
#              LOSS10 > LossThresholdPercent
#   UP       - no failures and not degraded
#   INIT     - initial state before the first check
#
# Jitter is calculated and displayed but intentionally does NOT
# affect status/color (no baseline yet).
# =====================================================================

function Update-NodeState {
    param ([hashtable]$Node, [hashtable]$PingResult)

    $id    = $Node.ID
    $state = $NodeState[$id]
    $daily = $DailyStats[$id]

    $timestamp = Get-NowStamp

    # Defensive: a missing result is treated as a failed ping.
    if ($null -eq $PingResult) { $PingResult = @{ Success = $false; Latency = $null } }
    $result = $PingResult

    # Every ping counts toward the daily report totals.
    $daily.TotalAttempts++

    if ($result.Success) {
        $state.CurrentLatency     = $result.Latency
        $state.ConsecutiveFails   = 0
        $state.LastSuccessfulPing = $timestamp
        $state.LatencyHistory += $result.Latency
        $state.PingHistory    += $true

        # Chart value: real latency, capped at the chart ceiling so it
        # never plots above the Y axis.
        $state.ChartHistory += [math]::Min([int]$result.Latency, $ChartYMax)

        $daily.SuccessfulAttempts++
        $daily.LatencySumMs += $result.Latency
        $daily.LatencySamples++
    }
    else {
        $state.CurrentLatency = $null
        $state.ConsecutiveFails++
        $state.PingHistory += $false

        # Chart value for a drop/timeout (ceiling by default so outages
        # spike to the top of the chart).
        $state.ChartHistory += $ChartTimeoutValue

        $daily.FailedAttempts++
    }

    # Trim histories to the last $HistoryLimit entries.
    if ($state.LatencyHistory.Count -gt $HistoryLimit) {
        $state.LatencyHistory = $state.LatencyHistory[-$HistoryLimit..-1]
    }
    if ($state.PingHistory.Count -gt $HistoryLimit) {
        $state.PingHistory = $state.PingHistory[-$HistoryLimit..-1]
    }
    if ($state.ChartHistory.Count -gt $ChartHistoryLimit) {
        $state.ChartHistory = $state.ChartHistory[-$ChartHistoryLimit..-1]
    }

    # AVG10 and JITTER use SUCCESSFUL replies only. Failed pings have
    # no latency value, so including them would corrupt the average.
    if ($state.LatencyHistory.Count -gt 0) {
        $state.AvgLatency = [math]::Round(($state.LatencyHistory | Measure-Object -Average).Average, 1)
        $maxLatency = ($state.LatencyHistory | Measure-Object -Maximum).Maximum
        $minLatency = ($state.LatencyHistory | Measure-Object -Minimum).Minimum
        $state.Jitter = $maxLatency - $minLatency
    }
    else {
        $state.AvgLatency = "N/A"
        $state.Jitter     = "N/A"
    }

    # LOSS10 uses ALL of the last 10 attempts, including failures.
    if ($state.PingHistory.Count -gt 0) {
        $lossCount = ($state.PingHistory | Where-Object { $_ -eq $false }).Count
        $state.LossPercent = [math]::Round(($lossCount / $state.PingHistory.Count) * 100, 0)
    }
    else {
        $state.LossPercent = 0
    }

    # ----- Health status decision -----
    $oldStatus = $state.Status

    if ($state.ConsecutiveFails -ge $FailThreshold) {
        $state.Status = "DOWN"
    }
    elseif ($state.ConsecutiveFails -gt 0) {
        $state.Status = "WARNING"
    }
    elseif (
        ($state.AvgLatency -ne "N/A" -and $state.AvgLatency -gt $LatencyThresholdMs) -or
        ($state.LossPercent -gt $LossThresholdPercent)
    ) {
        $state.Status = "DEGRADED"
    }
    else {
        $state.Status = "UP"
    }

    # Report the transition. INIT -> UP is skipped (a healthy node at
    # startup is not an incident); INIT -> WARNING/DEGRADED/DOWN IS
    # reported because a sick node at startup matters.
    if ($state.Status -ne $oldStatus) {
        if (-not ($oldStatus -eq "INIT" -and $state.Status -eq "UP")) {
            switch ($state.Status) {
                "DOWN"     { $level = "Error"       }
                "DEGRADED" { $level = "Warning"     }
                "WARNING"  { $level = "Warning"     }
                default    { $level = "Information" }
            }
            Write-StatusChange -Node $Node -OldStatus $oldStatus -NewStatus $state.Status -Level $level
        }
    }

    $NodeState[$id]  = $state
    $DailyStats[$id] = $daily
}

# =====================================================================
# FUNCTION: Format-TileLine
# Pads/truncates one line of tile content so every tile is exactly
# $TileWidth characters wide (keeps the grid aligned).
# =====================================================================

function Format-TileLine {
    param ([string]$Text)
    $InnerWidth = $TileWidth - 4
    if ($Text.Length -gt $InnerWidth) {
        $Text = $Text.Substring(0, $InnerWidth)
    }
    return "| " + $Text.PadRight($InnerWidth) + " |"
}

# =====================================================================
# FUNCTION: Get-NodeTileLines
# Builds the 9 content lines displayed inside one node tile.
# "N/A" values are shown cleanly (no "N/Ams").
# =====================================================================

function Get-NodeTileLines {
    param ([hashtable]$Node)

    $state = $NodeState[$Node.ID]

    if ($null -ne $state.CurrentLatency) { $currentText = "$($state.CurrentLatency)ms" }
    else                                 { $currentText = "TIMEOUT" }

    if ($state.AvgLatency -eq "N/A") { $avgText = "N/A" } else { $avgText = "$($state.AvgLatency)ms" }
    if ($state.Jitter -eq "N/A")     { $jitterText = "N/A" } else { $jitterText = "$($state.Jitter)ms" }

    return @(
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
}

# =====================================================================
# FUNCTION: Write-TileGap
# Writes the spacing between node boxes. Always uses the black
# default background so gaps never pick up a tile color.
# =====================================================================

function Write-TileGap {
    Write-Host $TileGap `
        -ForegroundColor $DefaultForegroundColor `
        -BackgroundColor $DefaultBackgroundColor `
        -NoNewline
}

# =====================================================================
# FUNCTION: Draw-Dashboard
# Redraws the entire dashboard: header, 5x3 tile grid, footer.
# =====================================================================

function Draw-Dashboard {

    # Re-force default colors every refresh in case anything reset them.
    try {
        $Host.UI.RawUI.BackgroundColor = $DefaultBackgroundColor
        $Host.UI.RawUI.ForegroundColor = $DefaultForegroundColor
    }
    catch {}

    Clear-Host

    $now = Get-NowStamp

    $upCount       = ($NodeState.Values | Where-Object { $_.Status -eq "UP"       }).Count
    $warningCount  = ($NodeState.Values | Where-Object { $_.Status -eq "WARNING"  }).Count
    $degradedCount = ($NodeState.Values | Where-Object { $_.Status -eq "DEGRADED" }).Count
    $downCount     = ($NodeState.Values | Where-Object { $_.Status -eq "DOWN"     }).Count
    $initCount     = ($NodeState.Values | Where-Object { $_.Status -eq "INIT"     }).Count

    Write-Host "NOC SINGLE PANE TV DASHBOARD" `
        -ForegroundColor Cyan -BackgroundColor $DefaultBackgroundColor

    # Header summary line with color-coded counts for at-a-glance reads.
    Write-Host "Last Refresh: $now $TimeLabel | Total: $($Nodes.Count) | " `
        -ForegroundColor $DefaultForegroundColor -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host "UP: $upCount" `
        -ForegroundColor Green -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host "WARNING: $warningCount" `
        -ForegroundColor Magenta -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host "DEGRADED: $degradedCount" `
        -ForegroundColor Magenta -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host "DOWN: $downCount" `
        -ForegroundColor Red -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host " | " `
        -ForegroundColor $DefaultForegroundColor -BackgroundColor $DefaultBackgroundColor -NoNewline
    Write-Host "INIT: $initCount" `
        -ForegroundColor Cyan -BackgroundColor $DefaultBackgroundColor

    # ---- Reporting destination status ----
    # File destination line.
    Write-Host "Files   : " -ForegroundColor $DefaultForegroundColor -BackgroundColor $DefaultBackgroundColor -NoNewline
    if (-not $EnableFileReports) {
        Write-Host "disabled" -ForegroundColor DarkGray -BackgroundColor $DefaultBackgroundColor
    }
    elseif ($script:FileReady) {
        Write-Host $script:FileTargetText -ForegroundColor Green -BackgroundColor $DefaultBackgroundColor
    }
    else {
        Write-Host $script:FileTargetText -ForegroundColor Red -BackgroundColor $DefaultBackgroundColor
    }

    # Event Log destination line.
    Write-Host "EventLog: " -ForegroundColor $DefaultForegroundColor -BackgroundColor $DefaultBackgroundColor -NoNewline
    if (-not $EnableEventLog) {
        Write-Host "disabled" -ForegroundColor DarkGray -BackgroundColor $DefaultBackgroundColor
    }
    elseif ($script:EventLogReady) {
        Write-Host $script:EventLogTargetText -ForegroundColor Green -BackgroundColor $DefaultBackgroundColor
    }
    else {
        Write-Host $script:EventLogTargetText -ForegroundColor Red -BackgroundColor $DefaultBackgroundColor
    }

    # Current Tue-Mon report week (in the active time standard).
    $weekStart = Get-WeekStart -Date (Get-Now)
    $weekEnd   = $weekStart.AddDays(6)
    Write-Host "Report week ($TimeLabel): Tuesday $($weekStart.ToString('yyyy-MM-dd')) 00:00 to Monday $($weekEnd.ToString('yyyy-MM-dd')) 23:59" `
        -ForegroundColor DarkGray -BackgroundColor $DefaultBackgroundColor

    Write-Host "" -BackgroundColor $DefaultBackgroundColor

    $TopBorder    = "+" + ("-" * ($TileWidth - 2)) + "+"
    $BottomBorder = $TopBorder

    for ($row = 0; $row -lt $Rows; $row++) {

        $rowNodes = @()
        for ($col = 0; $col -lt $Columns; $col++) {
            $index = ($row * $Columns) + $col
            if ($index -lt $Nodes.Count) { $rowNodes += $Nodes[$index] }
        }

        # Top border row
        foreach ($node in $rowNodes) {
            $status = $NodeState[$node.ID].Status
            Write-Host $TopBorder `
                -ForegroundColor (Get-SafeFgColor -Status $status) `
                -BackgroundColor (Get-SafeBgColor -Status $status) -NoNewline
            Write-TileGap
        }
        Write-Host "" -BackgroundColor $DefaultBackgroundColor

        # Each tile has 9 content lines (see Get-NodeTileLines).
        for ($lineIndex = 0; $lineIndex -lt 9; $lineIndex++) {
            foreach ($node in $rowNodes) {
                $status    = $NodeState[$node.ID].Status
                $tileLines = Get-NodeTileLines -Node $node
                $text      = Format-TileLine $tileLines[$lineIndex]
                Write-Host $text `
                    -ForegroundColor (Get-SafeFgColor -Status $status) `
                    -BackgroundColor (Get-SafeBgColor -Status $status) -NoNewline
                Write-TileGap
            }
            Write-Host "" -BackgroundColor $DefaultBackgroundColor
        }

        # Bottom border row
        foreach ($node in $rowNodes) {
            $status = $NodeState[$node.ID].Status
            Write-Host $BottomBorder `
                -ForegroundColor (Get-SafeFgColor -Status $status) `
                -BackgroundColor (Get-SafeBgColor -Status $status) -NoNewline
            Write-TileGap
        }
        Write-Host "" -BackgroundColor $DefaultBackgroundColor
        Write-Host "" -BackgroundColor $DefaultBackgroundColor
    }

    Write-Host "Press CTRL + C to stop monitoring." `
        -ForegroundColor DarkGray -BackgroundColor $DefaultBackgroundColor
}

# =====================================================================
# FUNCTION: Reset-DailyCounters
# Zeroes the cumulative daily counters at the rollover after the
# previous day's final report has been written.
# =====================================================================

function Reset-DailyCounters {
    foreach ($node in $Nodes) {
        $DailyStats[$node.ID] = @{
            TotalAttempts      = 0
            SuccessfulAttempts = 0
            FailedAttempts     = 0
            LatencySumMs       = 0
            LatencySamples     = 0
        }
    }
}

# =====================================================================
# FUNCTION: Check-DailyReportRollover
# Called once per polling cycle. When the report-day changes (at
# 00:00 in the active time standard):
#   1. Write the FINAL daily report for the finished day.
#   2. If the finished day was a MONDAY, the Tue-Mon report week is
#      complete - write the weekly report for it.
#   3. Reset the daily counters.
#   4. Start tracking the new day.
# =====================================================================

function Check-DailyReportRollover {

    $today = Get-TodayStamp

    if ($today -ne $script:CurrentReportDate) {

        $finishedDay = [datetime]::ParseExact($script:CurrentReportDate, "yyyy-MM-dd", $null)

        # 1. Official daily record for the finished day.
        Save-DailyReport -ReportDate $script:CurrentReportDate -Final

        # 2. Monday is day 7 of the Tue-Mon report week, so a finished
        #    Monday means a finished week.
        if ($finishedDay.DayOfWeek -eq [DayOfWeek]::Monday) {
            Save-WeeklyReport -ForDate $finishedDay
        }

        # 3. Fresh counters for the new day.
        Reset-DailyCounters

        # 4. Begin tracking the new day.
        $script:CurrentReportDate = $today
    }
}

# =====================================================================
# =====================================================================
#   LIVE LATENCY LINE CHART (optional pop-up window)
# =====================================================================
# =====================================================================
# A WinForms line chart, shown in its OWN window next to the console
# dashboard, so a single script gives both the text grid and a graph.
#
# Design:
#   - The console main thread keeps pinging (in parallel) and drawing.
#   - The chart runs on a SEPARATE STA runspace with its own message
#     loop, so it does not block the console loop.
#   - They share one synchronized hashtable ($script:ChartSync). Each
#     cycle the console copies every node's ChartHistory into it; the
#     chart's 2-second timer reads it and redraws. ONE data source,
#     no extra pinging.
#
# X axis = last $ChartHistoryLimit results (0..9).
# Y axis = $ChartYMin .. $ChartYMax (0..2500 ms).
# =====================================================================

# ---------------------------------------------------------------------
# Start-LiveChart
# Loads the charting assemblies and launches the chart window on a
# background runspace. If charting is unavailable (headless host, no
# WinForms), it quietly disables the chart and the console dashboard
# keeps running.
# ---------------------------------------------------------------------
function Start-LiveChart {
    if (-not $EnableLiveChart) { return }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction Stop
    }
    catch {
        # No GUI/charting available - run console-only.
        $script:ChartSync = $null
        return
    }

    # Shared, thread-safe state handed to the GUI runspace.
    $sync = [hashtable]::Synchronized(@{})
    $sync.IsRunning    = $true
    $sync.Nodes        = $Nodes
    $sync.NodeColors   = $NodeColors
    $sync.YMin         = $ChartYMin
    $sync.YMax         = $ChartYMax
    $sync.HistoryLimit = $ChartHistoryLimit
    $sync.ChartData    = [hashtable]::Synchronized(@{})
    foreach ($node in $Nodes) {
        # Pre-fill so the chart has something to draw before cycle 1.
        $sync.ChartData[$node.ID] = @(0) * $ChartHistoryLimit
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"      # WinForms requires single-thread apartment
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    $rs.SessionStateProxy.SetVariable("syncHash", $sync)

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript({
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Windows.Forms.DataVisualization

        $form = New-Object System.Windows.Forms.Form
        $form.Text = "NOC Live Node Latency (last $($syncHash.HistoryLimit) results)"
        $form.Width = 1400
        $form.Height = 700
        $form.StartPosition = "CenterScreen"

        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Dock = "Fill"

        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
        $area.AxisY.Minimum  = $syncHash.YMin
        $area.AxisY.Maximum  = $syncHash.YMax
        $area.AxisY.Title    = "Latency (ms)"
        $area.AxisY.Interval = 250
        $area.AxisX.Minimum  = 0
        $area.AxisX.Maximum  = $syncHash.HistoryLimit - 1
        $area.AxisX.Interval = 1
        $area.AxisX.Title    = "Last $($syncHash.HistoryLimit) results"
        $chart.ChartAreas.Add($area)
        $form.Controls.Add($chart)

        $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
        $legend.Docking = "Right"
        $legend.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
        $chart.Legends.Add($legend)

        # One line series per node, in its configured color.
        foreach ($node in $syncHash.Nodes) {
            $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
            $series.Name       = $node.NodeName
            $series.ChartType  = "Line"
            $series.BorderWidth = 4               # thick lines for TV screens
            try {
                $series.Color = [System.Drawing.ColorTranslator]::FromHtml($syncHash.NodeColors[$node.ID])
            }
            catch {}
            $chart.Series.Add($series)
        }

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 2000     # redraw every 2 seconds
        $timer.Add_Tick({
            # Console asked us to stop (CTRL + C) -> close the window.
            if (-not $syncHash.IsRunning) { $timer.Stop(); $form.Close(); return }

            foreach ($node in $syncHash.Nodes) {
                $name = $node.NodeName
                $data = $syncHash.ChartData[$node.ID]
                $chart.Series[$name].Points.Clear()
                for ($i = 0; $i -lt $data.Count; $i++) {
                    $null = $chart.Series[$name].Points.AddXY($i, $data[$i])
                }
            }
            $chart.Invalidate()
        })

        # If the operator closes the chart window, tell the rest of the
        # script (the console dashboard keeps running regardless).
        $form.Add_FormClosing({
            $timer.Stop()
            $syncHash.IsRunning = $false
        })

        $timer.Start()
        [System.Windows.Forms.Application]::Run($form)
    })

    $script:ChartSync     = $sync
    $script:ChartRunspace = $rs
    $script:ChartPs       = $ps
    $script:ChartHandle   = $ps.BeginInvoke()
}

# ---------------------------------------------------------------------
# Update-ChartData
# Copies each node's latest ChartHistory into the shared hashtable for
# the GUI to read. A fresh array snapshot per node means the chart
# never sees a half-updated series.
# ---------------------------------------------------------------------
function Update-ChartData {
    if ($null -eq $script:ChartSync) { return }
    if (-not $script:ChartSync.IsRunning) { return }
    foreach ($node in $Nodes) {
        $script:ChartSync.ChartData[$node.ID] = @($NodeState[$node.ID].ChartHistory)
    }
}

# ---------------------------------------------------------------------
# Stop-LiveChart
# Signals the GUI to close and tears down the runspace. Safe to call
# even if the chart never started or was already closed.
# ---------------------------------------------------------------------
function Stop-LiveChart {
    if ($null -eq $script:ChartSync) { return }
    try { $script:ChartSync.IsRunning = $false } catch {}
    try { if ($script:ChartPs -and $script:ChartHandle) { $null = $script:ChartPs.EndInvoke($script:ChartHandle) } } catch {}
    try { if ($script:ChartPs) { $script:ChartPs.Dispose() } } catch {}
    try { if ($script:ChartRunspace) { $script:ChartRunspace.Close(); $script:ChartRunspace.Dispose() } } catch {}
}

# =====================================================================
# STARTUP SEQUENCE + MAIN LOOP
# =====================================================================
# Order each cycle:
#   1. Start a stopwatch (used to keep a steady refresh cadence).
#   2. Check for rollover (finalize old day / old week).
#   3. Ping ALL nodes in parallel (Invoke-AllPings), then update each
#      node from its result; status changes are reported to every
#      enabled destination as they happen.
#   4. Push the latest latencies to the live chart (if enabled).
#   5. Redraw the dashboard.
#   6. Persist counters for crash protection:
#        Files    - rewrite the daily CSV every cycle (cheap).
#        EventLog - write a snapshot every $SnapshotIntervalMinutes.
#   7. Sleep only the time LEFT in the interval, so the cycle targets
#      a true ~$RefreshIntervalSeconds cadence (see timing note up top).
# =====================================================================

Initialize-Reporting

# Resume today's counters if the script restarted mid-day.
Load-TodayCounters

# Build/refresh the current week's report once at startup so it
# reflects any daily reports created while the script was not running.
Save-WeeklyReport

# Launch the live latency chart window (no-op if disabled/unavailable).
Start-LiveChart

try {
    while ($true) {

        # Stopwatch is independent of Zulu/local time and never goes
        # backwards, so it is the right tool for cadence timing.
        $cycleTimer = [System.Diagnostics.Stopwatch]::StartNew()

        Check-DailyReportRollover

        # Fire all pings at once, then update each node from its result.
        $pingResults = Invoke-AllPings -NodeList $Nodes -TimeoutMs $PingTimeoutMs
        foreach ($node in $Nodes) {
            Update-NodeState -Node $node -PingResult $pingResults[$node.ID]
        }

        # Hand the fresh latencies to the chart window.
        Update-ChartData

        Draw-Dashboard

        # File daily CSV: cheap, rewrite every cycle for crash safety.
        if ($script:FileReady) {
            Save-DailyReport_File
        }

        # Event Log snapshot: throttled so the log is not flooded.
        if ($script:EventLogReady) {
            if (((Get-Now) - $script:LastSnapshotTime).TotalMinutes -ge $SnapshotIntervalMinutes) {
                Save-DailyReport_EventLog
                $script:LastSnapshotTime = Get-Now
            }
        }

        # Sleep only the time LEFT in this interval so the cycle holds
        # a true ~$RefreshIntervalSeconds cadence. If the work already
        # took longer than the interval, skip sleeping (the next cycle
        # starts immediately).
        $remainingMs = [int](($RefreshIntervalSeconds * 1000) - $cycleTimer.Elapsed.TotalMilliseconds)
        if ($remainingMs -gt 0) {
            Start-Sleep -Milliseconds $remainingMs
        }
    }
}
finally {
    # Runs on CTRL + C: save a final daily report to every enabled
    # destination so no counting is lost on the way out, and close the
    # chart window.
    if ($script:FileReady)     { Save-DailyReport_File }
    if ($script:EventLogReady) { Save-DailyReport_EventLog }
    Stop-LiveChart
}

# NetMonTool — Architecture Deep-Dive

This document explains *how* and *why* NetMonTool is built the way it is. It's
aimed at engineers reviewing the code, and at anyone wanting to extend it.

---

## Design Goals

Everything in the design traces back to four constraints from real NOC and
secured-network environments:

1. **Zero dependencies** — must run on a stock Windows + PowerShell 5.1 host
   with nothing to install. No modules, no agents, no internet.
2. **Single-file portability** — must be copyable to an air-gapped or
   locked-down host as one `.ps1`.
3. **Never crash the dashboard** — a transient failure (a locked CSV, an
   unreachable share, one bad ping) must never take down the live view.
4. **Leadership-grade reporting** — availability and latency numbers must be
   accurate, durable across restarts, and accessible on a share drive.

---

## High-Level Data Flow

```
                    ┌─────────────────────────────┐
                    │        MAIN LOOP            │
                    │   (every ~5 seconds)        │
                    └──────────────┬──────────────┘
                                   │
            ┌──────────────────────┼──────────────────────┐
            ▼                      ▼                       ▼
   ┌─────────────────┐   ┌──────────────────┐   ┌────────────────────┐
   │ Invoke-AllPings │   │ Update-NodeState │   │   Draw-Dashboard   │
   │  (parallel)     │──▶│  live + counters │──▶│  console tiles     │
   └─────────────────┘   └────────┬─────────┘   └────────────────────┘
                                  │
                                  ▼
                       ┌──────────────────────┐
                       │   Write-StatusChange │  (on transition)
                       │   Save-DailyReport   │  (every cycle)
                       └──────────┬───────────┘
                                  │  fan-out
                     ┌────────────┴────────────┐
                     ▼                         ▼
            ┌─────────────────┐       ┌──────────────────┐
            │  CSV FILES      │       │  WINDOWS EVENT   │
            │  daily/weekly/  │       │  LOG (Event      │
            │  events         │       │  Viewer)         │
            └─────────────────┘       └──────────────────┘
```

---

## Component 1 — The Parallel Ping Engine

**Function:** `Invoke-AllPings`

The single most important design decision in V4. V3 pinged nodes one at a
time (sequential). The problem: with a 2.5-second timeout, a handful of dead
nodes could stretch a single refresh cycle to 15+ seconds, because the script
waited for each timeout *in series*.

V4 fixes this with **asynchronous, concurrent pinging**:

1. For each node, a dedicated `System.Net.NetworkInformation.Ping` object is
   created and `SendPingAsync(ip, timeout)` is called. This returns a
   `Task` immediately without blocking.
2. All tasks are then awaited *together* with `Task.WaitAll`.
3. Because every ping self-times-out at `$PingTimeoutMs` and they all run at
   once, the whole batch completes in roughly the **longest single ping**,
   not the **sum** of all pings.

**Result:** even if all 15 nodes are down, the batch resolves in about one
timeout window (~1.5s) instead of 15 × 1.5s.

**Why one Ping object per node:** a single `Ping` instance cannot run two
async operations simultaneously — it throws. So each node gets its own
object, created and disposed within the function to avoid handle leaks.

**Failure handling:** any non-`Success` reply, timeout, faulted task, or
exception is normalized to `@{ Success = $false; Latency = $null }`. The
caller never has to special-case errors.

---

## Component 2 — The Two-Tier State Model

Each node carries **two** separate state objects, by design:

### `$NodeState` — short-term, for the live dashboard
Holds only the **last 10 attempts**: latency history, ping success/fail
history, chart history, consecutive fails, current status. This is what
drives the colored tiles and the AVG10 / LOSS10 / JITTER figures. It's a
rolling window — old data falls off.

### `$DailyStats` — cumulative, for reporting
Holds **running totals for the whole report day**: total attempts,
successful attempts, failed attempts, and crucially `LatencySumMs` +
`LatencySamples`.

**Why separate them?** The dashboard wants *recent* behavior ("is this node
healthy right now?"). Reporting wants *cumulative* truth ("what was this
node's availability all day?"). Mixing the two would force one to compromise.
Keeping them separate means the rolling window can be trimmed aggressively
while the daily counters keep accumulating untouched.

---

## Component 3 — Weighted Weekly Averages

A subtle but important correctness detail.

The naive way to compute a weekly average latency is to average the seven
daily averages. **That's wrong** when the days have different sample counts —
a day with 5 samples gets the same weight as a day with 50,000.

NetMonTool avoids this by carrying the **raw building blocks** through to the
weekly rollup:

```
weekly_avg = Σ(daily LatencySumMs) / Σ(daily LatencySamples)
```

Each daily record stores `LatencySumMs` (sum of all successful latencies)
and `LatencySamples` (count). The weekly aggregator (`Get-WeightedTotals`)
sums those raw numbers across the Tuesday–Monday window and divides once at
the end. This produces a **true sample-weighted mean**, identical to what you'd
get if you'd averaged every individual ping for the whole week.

---

## Component 4 — Dual-Destination Reporting

**Dispatchers:** `Write-StatusChange`, `Save-DailyReport`, `Save-WeeklyReport`

Reporting is designed so that **File** and **Event Log** destinations are
fully independent:

- Each has its own readiness flag (`$script:FileReady`,
  `$script:EventLogReady`) set at init.
- Each dispatcher checks both flags and writes to whichever are ready.
- If the share drive is unreachable, Event Log still logs. If the script
  isn't run as admin (so the Event Log can't be created), CSV still writes.
  The live dashboard runs regardless of both.

### File destination
- `daily/noc_daily_DATE.csv` — rewritten every cycle (cheap, crash-safe).
- `weekly/noc_weekly_TUESDAY.csv` — recomputed from the daily files.
- `events/noc_events_DATE.csv` — appended on each status change.
- A startup **write-probe** drops and deletes a temp file to confirm the path
  (local, mapped drive, or UNC share) is actually writable — so an
  unreachable share fails *loudly at init* rather than *silently at runtime*.

### Event Log destination
- Custom log `NOCMonitor`, source `NOCMonitor-TV`.
- Status changes logged with severity-appropriate Event IDs (Error for DOWN,
  Warning for WARNING/DEGRADED, Information for UP).
- Snapshot/summary events store data as `Key=Value` lines — human-readable in
  Event Viewer *and* machine-parseable on reload.
- Event Log writes are **throttled** to every few minutes (it can't absorb 15
  entries every 5 seconds); CSV carries the high-frequency load instead.

---

## Component 5 — The Zulu Time Funnel

Every date, timestamp, and week boundary in the entire script flows through
two helpers:

```powershell
function Get-Now      { if ($UseZuluTime) { [DateTime]::UtcNow } else { Get-Date } }
function Get-NowStamp { (Get-Now).ToString("yyyy-MM-dd HH:mm:ss") }
```

Because *nothing* calls `Get-Date` directly for reporting, flipping a single
`$UseZuluTime` toggle switches the whole tool — dashboard clock, CSV dates,
week boundaries, event timestamps — between UTC and local time consistently.
UTC is the default because secured / CSfC / multi-site environments
standardize on Zulu to avoid timezone ambiguity across sites.

Report weeks are defined as **Tuesday 00:00Z → Monday 23:59Z**. The
`Get-WeekStart` helper uses modulo arithmetic on .NET's `DayOfWeek`
numbering to find the Tuesday that anchors any given date's week.

---

## Component 6 — Crash Safety & Resume

The dashboard is expected to run for days or weeks on a NOC wall display.
Two mechanisms keep reporting durable:

1. **Rewrite-every-cycle daily CSV.** The current day's counters are written
   out every loop. If the host reboots, at most ~5 seconds of counting is
   lost.
2. **Resume on startup.** `Load-TodayCounters` reads today's CSV (or the
   Event Log) back into `$DailyStats` at launch, so a mid-day restart picks
   up where it left off instead of resetting leadership numbers to zero.

A `finally` block around the main loop guarantees a **final report write** to
every enabled destination when the operator presses CTRL + C — no counting is
lost on a clean exit.

---

## Component 7 — The Live Chart (Optional)

When `$EnableLiveChart = $true`, the script spins up a **WinForms chart in a
separate runspace** so the GUI's message loop doesn't block the console
dashboard. A synchronized hashtable is the hand-off point: the main loop
writes each node's latest latency window into it (`Update-ChartData`), and a
2-second GUI timer reads from it to redraw the lines. Timeouts plot at the
chart ceiling so outages spike visibly to the top of the graph.

If WinForms isn't available (e.g. a headless host), the chart simply doesn't
start and the console dashboard continues unaffected — consistent with the
"never crash the dashboard" rule.

---

## Summary

NetMonTool's architecture is a study in doing a lot with deliberately little:
native .NET async for performance, a two-tier state model for correctness,
independent reporting destinations for resilience, and a single time funnel
for consistency — all in one dependency-free file that drops onto any Windows
box and runs.

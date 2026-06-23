# Changelog

All notable changes to **NetMonTool** are documented here.
This project follows [Semantic Versioning](https://semver.org/) and the
[Keep a Changelog](https://keepachangelog.com/) format.

---

## [4.0.0] — 2025

Major release. The tool evolves from a live dashboard into a complete
monitoring **and reporting** solution.

### Added
- **Parallel ping polling** (`Invoke-AllPings`) using .NET `SendPingAsync`
  with `Task.WaitAll`. All nodes are pinged concurrently, so a full cycle
  finishes in roughly the longest single ping instead of the sum of every
  ping. Refresh cadence is now a true ~5 seconds even when multiple nodes
  are timing out.
- **Daily CSV reporting** — per-node total/successful/failed attempts,
  drop %, availability %, and average latency. Rewritten every cycle for
  crash safety.
- **Weekly CSV reporting** — Tuesday-to-Monday rollup with a correctly
  **weighted** average latency (carries `LatencySumMs` + `LatencySamples`
  rather than averaging daily averages).
- **Events CSV** — incident timeline; one row per node status change.
- **Windows Event Log integration** — status changes and daily/weekly
  summaries written to a custom `NOCMonitor` log visible in Event Viewer
  (Applications and Services Logs). Includes a documented Event ID scheme.
- **Live latency line chart** — optional WinForms pop-up, one colored
  line per node, fed by the same pings as the dashboard (no extra pinging).
- **Zulu (UTC) time standard** — all report dates, week boundaries, and
  timestamps flow through a single `Get-Now` funnel; toggle with
  `$UseZuluTime`.
- **Crash-safe resume** — `Load-TodayCounters` reloads the day's counters
  after a mid-day restart so reporting numbers never reset to zero.
- **Startup write-probe** — verifies the report path (local, mapped, or
  UNC share) is writable at init so an unreachable share fails loudly
  instead of silently dropping data.
- **Independent destination readiness flags** — File and Event Log each
  fail independently; one being unavailable never disables the other or
  the live dashboard.

### Changed
- Reporting is now dispatched through fan-out functions
  (`Write-StatusChange`, `Save-DailyReport`, `Save-WeeklyReport`) that
  write to every enabled destination.
- `$PingTimeoutMs` default lowered to `1500` (from 2500) to tighten the
  refresh cadence now that polling is parallel.

### Known Issues / Notes
- `WARNING` and `DEGRADED` currently map to the same tile background
  (`DarkMagenta`). `DarkYellow` was intentionally removed because it
  renders as unreadable white on some consoles; a third distinct
  console-safe color is planned. (Roadmap)
- Several function names (`Draw-Dashboard`, `Load-TodayCounters`,
  `Save-WeeklyReport`) use non-approved PowerShell verbs. A rename pass to
  `Write-`/`Import-`/`Export-` for full `Get-Verb` compliance is planned.
  (Roadmap)

---

## [3.0.0] — 2025

Refinement release focused on display clarity and PowerShell conventions.

### Added
- **Color-coded header summary** — UP / WARNING / DEGRADED / DOWN / INIT
  counts render in their matching console colors for at-a-glance status.

### Changed
- **DEGRADED** status given its own color (`DarkMagenta`), making it
  visually distinct from WARNING on a NOC TV display.
- Renamed `Draw-Dashboard` → `Write-Dashboard` to use an approved
  PowerShell verb.

### Fixed
- **Clean N/A display** — `AVG10` and `JITTER` now render `N/A` instead of
  the malformed `N/Ams` before enough ping history exists.

---

## [2.0.0] — 2025

### Added
- Configurable thresholds (fail count, latency, packet loss).
- Per-node jitter and last-successful-ping tracking.

---

## [1.0.0] — 2025

### Added
- Initial release: sequential ICMP polling, 5×3 NOC TV grid layout,
  color-coded status tiles, per-node latency and packet-loss tracking.

[4.0.0]: https://github.com/jariax/NetMonTool/releases/tag/v4.0.0
[3.0.0]: https://github.com/jariax/NetMonTool/releases/tag/v3.0.0
[2.0.0]: https://github.com/jariax/NetMonTool/releases/tag/v2.0.0
[1.0.0]: https://github.com/jariax/NetMonTool/releases/tag/v1.0.0

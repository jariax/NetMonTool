<h1 align="center">🖥️ NetMonTool — NOC Single-Pane Dashboard</h1>

<p align="center">
  <b>Real-time, zero-dependency network monitoring + performance reporting for NOC operations</b><br/>
  <i>Built in PowerShell by a Senior Network Engineer — runs anywhere Windows does.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Language-PowerShell%205.1-blue?style=flat-square&logo=powershell" />
  <img src="https://img.shields.io/badge/Platform-Windows-lightgrey?style=flat-square&logo=windows" />
  <img src="https://img.shields.io/badge/Dependencies-None-success?style=flat-square" />
  <img src="https://img.shields.io/badge/Environment-NOC%20%7C%20CSfC%20%7C%20Enterprise-darkgreen?style=flat-square" />
  <img src="https://img.shields.io/badge/Version-4.0-informational?style=flat-square" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" />
</p>

---

## 📋 Overview

**NetMonTool** is a single-file PowerShell tool that turns any Windows console into a live **NOC (Network Operations Center) dashboard** — and now, as of V4, a full **performance reporting engine**.

It monitors up to 15 network nodes in real time, displays a color-coded single pane of glass, and records daily/weekly availability and latency metrics to **CSV files** and the **Windows Event Log** — with **zero external dependencies**. No agents, no licenses, no install. Just PowerShell.

Built from hands-on experience supporting mission-critical and secured (CSfC) networks, it's designed to deliver the visibility you'd expect from enterprise platforms like SolarWinds or PRTG, in environments where those tools aren't available, aren't approved, or aren't in the budget.

---

## ✨ What's New in V4

V4 is a major release that takes the tool from a live dashboard to a complete monitoring + reporting solution:

- ⚡ **Parallel ping polling** — all nodes are pinged simultaneously via async .NET, giving a true ~5-second refresh regardless of how many nodes are timing out (V3 was sequential and slowed down under failures)
- 📊 **Daily & weekly CSV reporting** — automatic availability %, drop %, and weighted average latency, share-drive friendly for leadership visibility
- 📁 **Event timeline logging** — every status change written to a clean, openable incident CSV
- 🪟 **Windows Event Log integration** — node up/down/degraded events surface in Event Viewer as a backup audit trail
- 📈 **Live latency line chart** — optional pop-up graph window, one colored line per node
- 🕒 **Zulu (UTC) time standard** — default for secured/CSfC environments, with a single toggle for local time
- 💾 **Crash-safe & resumable** — counters reload after a mid-day restart so reporting numbers never reset to zero

> See the full [CHANGELOG](CHANGELOG.md) for the complete V3 → V4 history.

---

## 🖼️ Dashboard Preview

> **Live console output — 5 columns × 3 rows, NOC TV layout**

```
NOC SINGLE PANE TV DASHBOARD        Time: 2025-07-12 14:22:05Z
Files: \\server\share\NOC\reports   EventLog: NOCMonitor
Total: 15 | UP: 12 | WARNING: 1 | DEGRADED: 1 | DOWN: 1 | INIT: 0

+--------------------------------+    +--------------------------------+
| NODE_1                         |    | NODE_2                         |
| IP     : 192.168.1.1           |    | IP     : 10.0.0.1              |
| STATUS : UP                    |    | STATUS : DEGRADED              |
| CURR   : 12ms                  |    | CURR   : 540ms                 |
| AVG10  : 11.4ms                |    | AVG10  : 533.0ms               |
| LOSS10 : 0%                    |    | LOSS10 : 0%                    |
| JITTER : 4ms                   |    | JITTER : 88ms                  |
| FAILS  : 0                     |    | FAILS  : 0                     |
| LAST OK: 2025-07-12 14:22:04Z  |    | LAST OK: 2025-07-12 14:22:01Z  |
+--------------------------------+    +--------------------------------+
```

> 🟢 **UP** &nbsp;|&nbsp; 🟡 **WARNING** &nbsp;|&nbsp; 🟣 **DEGRADED** &nbsp;|&nbsp; 🔴 **DOWN** &nbsp;|&nbsp; 🔵 **INIT**

---

## 🚀 Features

| Capability | Detail |
|------------|--------|
| **Parallel polling** | `SendPingAsync` fires all nodes at once; batch finishes in ~longest single ping, not the sum |
| **Per-node metrics** | Current latency, 10-ping average, packet loss %, jitter, consecutive fails, last OK timestamp |
| **5 status states** | UP / WARNING / DEGRADED / DOWN / INIT — each color-coded |
| **Daily CSV** | Per-node attempts, successes, failures, drop %, availability %, avg latency |
| **Weekly CSV** | Tuesday–Monday rollup with correctly *weighted* average latency |
| **Events CSV** | Incident timeline — one row per status change |
| **Event Viewer** | Status changes + summaries logged under Applications and Services Logs > NOCMonitor |
| **Live chart** | Optional WinForms line graph, one color per node, refreshes every 2s |
| **Zulu time** | UTC-standard reporting by default; toggle `$UseZuluTime = $false` for local |
| **Crash-safe** | Daily CSV rewritten every cycle; counters reload on restart |
| **Zero dependencies** | Pure PowerShell 5.1 + native .NET — no modules, no installs |

---

## ⚙️ Quick Configuration

Everything lives in the clearly-marked config block at the top of the script.

```powershell
# ── Report Destinations (turn either/both on) ──────────
$UseZuluTime       = $true      # UTC reporting (recommended for secured envs)
$EnableFileReports = $true      # daily/weekly/events CSV — no admin needed
$ReportBasePath    = ""         # "" = ./reports, or a UNC share: \\server\share\NOC
$EnableEventLog    = $true      # Event Viewer logging — first run needs admin
$EnableLiveChart   = $true      # pop-up latency graph

# ── Nodes (add/remove freely) ──────────────────────────
$Nodes = @(
    @{ ID = 1; NodeName = "CORE-RTR-01"; IP = "192.168.1.1" },
    @{ ID = 2; NodeName = "DIST-SW-01";  IP = "10.0.0.1"    },
)

# ── Thresholds ─────────────────────────────────────────
$FailThreshold          = 3     # consecutive fails before DOWN
$LatencyThresholdMs     = 500   # AVG10 above this = DEGRADED
$LossThresholdPercent   = 20    # LOSS10 above this = DEGRADED
$PingTimeoutMs          = 1500  # replies slower than this count as failure
$RefreshIntervalSeconds = 5     # target refresh cadence
```

---

## ▶️ How to Run

**Requirements:** Windows + PowerShell 5.1. CSV reporting needs **no admin**. Event Log destination needs the **first run as Administrator** to create the custom log (any user afterward).

```powershell
# Standard run (keeps window open)
powershell.exe -NoExit -ExecutionPolicy Bypass -File ".\NetMonTool_V4.ps1"

# First-time run WITH Event Log (right-click PowerShell > Run as Administrator)
powershell.exe -NoExit -ExecutionPolicy Bypass -File ".\NetMonTool_V4.ps1"
```

> **Stop monitoring:** Press `CTRL + C`. A final report is written to every enabled destination on the way out.

---

## 📊 Status Logic

| Status | Condition |
|--------|-----------|
| `INIT` | Node has not completed its first check |
| `UP` | Responding; latency and loss within thresholds |
| `WARNING` | 1–2 consecutive failed pings |
| `DEGRADED` | Reachable, but AVG10 > latency threshold OR LOSS10 > loss threshold |
| `DOWN` | ≥ 3 consecutive failed pings (configurable) |

---

## 📈 Reporting Outputs

```
reports/
├── daily/
│   └── noc_daily_2025-07-12.csv      # per-node counters, rewritten each cycle
├── weekly/
│   └── noc_weekly_2025-07-08.csv     # Tue–Mon rollup, weighted averages
└── events/
    └── noc_events_2025-07-12.csv     # incident timeline (status changes)
```

**Event Viewer:** `Applications and Services Logs > NOCMonitor`
Event IDs — `1001` UP · `2001` WARNING · `2002` DEGRADED · `3001` DOWN · `4000/4001` daily snapshot/final · `5001` weekly summary.

---

## 🧠 Architecture

The script is organized into clean layers: a parallel ping engine, a per-node state model (live vs. cumulative), and a reporting dispatcher that fans out to multiple destinations independently.

📐 **Full breakdown in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — covers the async polling model, the dual-destination reporting design, the weighted weekly-average approach, and the Zulu-time funnel.

---

## 🗺️ Roadmap

- [ ] Distinct WARNING vs DEGRADED tile colors (currently share a palette slot — see CHANGELOG notes)
- [ ] Approved-verb rename pass (`Draw-`/`Load-`/`Save-` → `Write-`/`Import-`/`Export-`) for full `Get-Verb` compliance
- [ ] Configurable grid sizes beyond 5×3
- [ ] Optional email / Teams webhook on DOWN transitions
- [ ] Jitter-based DEGRADED logic once a latency baseline is established

---

## 👤 Author

**Julio E. Arias Pabón** — Senior Network Engineer | TS/SCI | CCNA | Security+

Network engineering across DoD, JSOC, and enterprise environments. Transitioning into cloud networking, cybersecurity, and software development. This is part of an ongoing portfolio of practical, field-tested tooling.

---

## 📄 License

Released under the [MIT License](LICENSE). Free to use, fork, and adapt — attribution appreciated.

<h1 align="center">🖥️ NOC Monitor — Single Pane Dashboard</h1>

<p align="center">
  <b>Real-time network health monitoring dashboard built for NOC TV displays</b><br/>
  <i>Engineered by a Senior Network Engineer with 8+ years of hands-on infrastructure experience</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Language-PowerShell-blue?style=flat-square&logo=powershell" />
  <img src="https://img.shields.io/badge/Platform-Windows-lightgrey?style=flat-square&logo=windows" />
  <img src="https://img.shields.io/badge/Environment-NOC%20%7C%20Enterprise-darkgreen?style=flat-square" />
  <img src="https://img.shields.io/badge/Version-V3-informational?style=flat-square" />
  <img src="https://img.shields.io/badge/Status-Active-success?style=flat-square" />
</p>

---

## 📋 Description

**NOC Monitor** is a PowerShell-based, real-time network health dashboard designed for **NOC (Network Operations Center) TV displays**. It provides a clean, color-coded **single pane of glass** view of up to 15 network nodes simultaneously — **no third-party software, no GUI framework, no external dependencies.**

Built from operational experience supporting mission-critical networks, including DoD enterprise environments. This tool mirrors the visibility requirements of professional monitoring solutions like SolarWinds, delivered purely through the Windows console.

---

## 🖼️ Dashborads on display when deploying both scipts

> **Live console output — 5 columns × 3 rows, NOC TV layout**

![image alt text](https://github.com/jariax/NetMonTool/blob/main/Screenshot%20of%20aplication%20in%20operation.png?raw=true)


> 🟢 **UP** = DarkGreen &nbsp;|&nbsp; 🟡 **WARNING** = DarkYellow &nbsp;|&nbsp; 🟣 **DEGRADED** = DarkMagenta &nbsp;|&nbsp; 🔴 **DOWN** = DarkRed &nbsp;|&nbsp; 🔵 **INIT** = DarkCyan

---

## 🚀 Features

- **Real-time ICMP ping polling** using native .NET `System.Net.NetworkInformation.Ping`
- **Per-node metrics:** current latency, 10-ping average, packet loss %, jitter, consecutive fail count, last successful ping timestamp
- **Five distinct status states:** UP / WARNING / DEGRADED / DOWN / INIT — each with a unique tile color
- **Color-coded header bar:** summary counts (UP / WARNING / DEGRADED / DOWN / INIT) rendered in their matching console colors for at-a-glance NOC TV readability
- **Smart health logic:** status driven by consecutive failures, average latency threshold, and packet loss threshold
- **Clean N/A handling:** latency and jitter fields display `N/A` (not `N/Ams`) when no data is available yet
- **NOC TV layout:** configurable columns × rows grid with fixed-width tiles, optimized for wide displays (200 char console width)
- **Zero dependencies:** pure PowerShell — no modules, no APIs, no installs required
- **Graceful error handling:** ping timeouts, console resize failures, and unreachable nodes are all handled cleanly

---

## ⚙️ Configuration

All settings are at the top of the script — no editing required beyond this block.

```powershell
# ── Node List ──────────────────────────────────────────
$Nodes = @(
    @{ ID = 1; NodeName = "CORE-RTR-01"; IP = "192.168.1.1" },
    @{ ID = 2; NodeName = "DIST-SW-01";  IP = "10.0.0.1"    },
    # Add up to 15 nodes (5 cols x 3 rows)
)

# ── Thresholds ─────────────────────────────────────────
$FailThreshold        = 3      # Consecutive failures before DOWN
$LatencyThresholdMs   = 500    # Avg latency above this = DEGRADED
$LossThresholdPercent = 20     # Packet loss above this = DEGRADED

# ── Polling ────────────────────────────────────────────
$PingTimeoutMs          = 2500  # Per-ping timeout
$RefreshIntervalSeconds = 2     # Wait between full cycles
$HistoryLimit           = 10    # Pings retained for avg/loss calc

# ── Display ────────────────────────────────────────────
$Columns       = 5
$Rows          = 3
$ConsoleWidth  = 200
$ConsoleHeight = 45
```
---

## 📊 Status Logic

| Status | Tile Color | Header Color | Condition |
|--------|------------|--------------|-----------|
| `INIT` | 🔵 DarkCyan | Cyan | Node has not been polled yet |
| `UP` | 🟢 DarkGreen | Green | Responding, latency and loss within thresholds |
| `WARNING` | 🟡 DarkYellow | Yellow | 1–2 consecutive failed pings |
| `DEGRADED` | 🟣 DarkMagenta | Magenta | High avg latency OR high packet loss, but still responding |
| `DOWN` | 🔴 DarkRed | Red | ≥ 3 consecutive failed pings (configurable) |

> **V3 update:** DEGRADED now renders in `DarkMagenta` (tile) and `Magenta` (header count), making it visually distinct from WARNING (`DarkYellow`) on a NOC TV display.

---

## ⏱️ Polling Behavior — Important Note

This script uses **sequential polling** (one node at a time). This means the actual cycle time depends on how many nodes are unreachable:

| Scenario | Estimated Cycle Time |
|----------|----------------------|
| All 15 nodes respond fast | ~2–4 seconds |
| 1 node times out (2500ms) | ~4–7 seconds |
| 5 nodes time out | ~15–17 seconds |
| All 15 nodes time out | ~37–40 seconds |

> 💡 **Roadmap:** Upgrading to parallel polling via `ForEach-Object -Parallel` (PowerShell 7+) or `Start-Job` would guarantee consistent cycle times regardless of timeout count.

---

## 🛠️ Technologies Used

| Tool | Purpose |
|------|---------|
| **PowerShell 5.1+** | Core scripting language |
| **System.Net.NetworkInformation.Ping** | Native .NET ICMP ping |
| **Windows Console API** | `$Host.UI.RawUI` for display control |

---

## ▶️ How to Run - This applies to both scripts, resize to match your screen resolution if nessesary

**Requirements:** Windows with PowerShell 5.1 or later. Run as Administrator for best results.

```powershell
# Option 1 — Right-click the script and select "Run with PowerShell"

# Option 2 — From a PowerShell terminal
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\NOCMonitorDashboardV3.ps1

# Option 3 — From PowerShell 7 (pwsh)
pwsh -ExecutionPolicy Bypass -File .\NOCMonitorDashboardV3.ps1
```

> **Stop monitoring:** Press `CTRL + C` at any time.

---

## 📝 Changelog

### V3 — Current
- **DEGRADED status now uses `DarkMagenta`** — previously shared `DarkYellow` with WARNING, making the two states visually identical on a NOC TV display
- **Clean N/A display** — AVG10 and JITTER fields now correctly render `N/A` instead of `N/Ams` before enough ping history is available
- **Color-coded header summary** — UP / WARNING / DEGRADED / DOWN / INIT counts in the header bar now render in their matching console colors for instant at-a-glance status
- **Renamed `Draw-Dashboard` → `Write-Dashboard`** — `Draw` is not an approved PowerShell verb; corrected to follow PowerShell naming standards

### V1–V2
- Initial build: sequential ICMP polling, 5×3 NOC TV grid layout, per-node latency/loss/jitter tracking, color-coded tiles, configurable thresholds

---

## 🔌 Add-on script - NOC_LiveChart_Unified

### V1 - Current
- **Using this script will populate a line chart showing the live latency for each node with a legend**

---

## 🗺️ Roadmap / Known Limitations

- [ ] **Parallel polling** — replace sequential loop with `ForEach-Object -Parallel` (PS 7+) for true fixed-interval monitoring
- [ ] **Jitter accuracy** — current jitter = (max - min latency); true statistical jitter requires standard deviation calculation
- [ ] **Log to file** — export status history to CSV for post-incident review
- [ ] **Alert on state change** — email or Teams webhook notification on DOWN transitions
- [ ] **Dynamic node count** — support larger grids (6×4, 7×3, etc.) via config

---

## 👤 Author

**Julio E. Arias Pabon**
Senior Network Engineer | TS/SCI | CCNA | Security+

- 8+ years of network engineering experience across DoD, JSOC, and enterprise environments
- Specialties: Cisco routing/switching, SATCOM, STIG/RMF, Splunk, NetBrain, Problem Solver, Root Cause Troubleshooting
- Tech nerd future Solutions Architect

📧 julioarias1496@gmail.com

---

## 📄 License

This project is open for educational and professional portfolio purposes. Feel free to fork, adapt, and build on it — just give credit where it's due.

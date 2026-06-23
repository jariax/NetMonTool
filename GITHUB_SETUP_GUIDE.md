# GitHub Setup Guide — Updating NetMonTool to V4

This is your step-by-step for pushing the V4 update, adding the docs, and
creating clean tagged releases for v3.0 and v4.0. Follow top to bottom.

> Your repo: `https://github.com/jariax/NetMonTool`

---

## Part 1 — Add the New Files

Drop these into your local clone (or upload via the GitHub web UI):

```
NetMonTool/
├── README.md                          ← updated for V4
├── CHANGELOG.md                       ← new
├── CONTRIBUTING.md                    ← new
├── LICENSE                            ← new (MIT)
├── PSScriptAnalyzerSettings.psd1      ← new
├── NetMonTool_V4.ps1                  ← your script (rename if needed)
├── .github/
│   └── workflows/
│       └── lint.yml                   ← new (CI)
└── docs/
    └── ARCHITECTURE.md                ← new
```

If you work from the command line:

```bash
git clone https://github.com/jariax/NetMonTool.git
cd NetMonTool
# copy the new files in, then:
git add .
git commit -m "V4: add reporting engine, docs, CI linting, MIT license"
git push origin main
```

---

## Part 2 — Tag the Releases

Tags mark exact points in history. We'll tag both the V3 state and the new
V4 state so your release history is clean and professional.

> **If V3 was your last commit before this update**, tag it first *before*
> pushing V4 — or tag the specific older commit by its hash (see note below).

### Tag V4 (current):
```bash
git tag -a v4.0.0 -m "V4.0.0 — Parallel polling + CSV/Event Log reporting"
git push origin v4.0.0
```

### Tag V3 retroactively (by commit hash):
First find the commit where V3 lived:
```bash
git log --oneline
```
Copy the hash of the V3 commit, then:
```bash
git tag -a v3.0.0 <COMMIT_HASH> -m "V3.0.0 — Color-coded header, DEGRADED color, N/A fix"
git push origin v3.0.0
```

> No separate V3 commit? That's fine — just create the v4.0.0 tag now and
> start clean versioning from here. Tags only matter going forward.

---

## Part 3 — Create the GitHub Releases

On your repo page: **Releases** (right sidebar) → **Draft a new release**.
Pick the tag, paste the notes below, publish.

### ─────────── Release: v4.0.0 ───────────
**Title:** `v4.0.0 — Reporting Engine + Parallel Polling`

**Notes (paste this):**
```markdown
## NetMonTool V4.0.0

Major release: NetMonTool goes from a live dashboard to a complete
monitoring **and reporting** solution — still zero-dependency, still a
single file.

### Highlights
- ⚡ **Parallel ping polling** — true ~5s refresh regardless of how many
  nodes are down (V3 was sequential and slowed under failures)
- 📊 **Daily & weekly CSV reporting** — availability %, drop %, and
  correctly *weighted* average latency, share-drive friendly
- 📁 **Events CSV** — clean incident timeline of every status change
- 🪟 **Windows Event Log integration** — events surface in Event Viewer
- 📈 **Live latency chart** — optional WinForms graph, one line per node
- 🕒 **Zulu (UTC) time standard** — single toggle, ideal for secured envs
- 💾 **Crash-safe & resumable** — counters survive a mid-day restart

### Notes
- WARNING and DEGRADED currently share a tile color; a distinct
  console-safe color is planned.
- An approved-verb rename pass is on the roadmap.

See the [CHANGELOG](CHANGELOG.md) and
[architecture deep-dive](docs/ARCHITECTURE.md) for full detail.
```

### ─────────── Release: v3.0.0 ───────────
**Title:** `v3.0.0 — Display Clarity + PowerShell Conventions`

**Notes (paste this):**
```markdown
## NetMonTool V3.0.0

Refinement release focused on dashboard readability and PowerShell
conventions.

### Changes
- 🟣 **DEGRADED** given its own color (DarkMagenta), distinct from WARNING
- 🎨 **Color-coded header summary** — status counts in matching colors
- 🔤 Renamed `Draw-Dashboard` → `Write-Dashboard` (approved verb)
- 🐛 Fixed `N/Ams` → clean `N/A` display for AVG10 and JITTER
```

---

## Part 4 — Polish the Repo Page

These small touches make a big professional impression:

1. **About section** (gear icon, top-right of repo): add a one-line
   description and topics:
   `powershell`, `network-monitoring`, `noc`, `dashboard`, `sysadmin`,
   `network-engineering`, `windows`, `icmp`, `monitoring-tool`
2. **Pin the repo** to your GitHub profile (profile → Customize your pins).
3. **Add a screenshot** — take a real photo/capture of the dashboard running
   with colored tiles, drop it in a `docs/` or `assets/` folder, and the
   README preview will come alive.
4. Confirm the **Actions** tab shows the lint workflow running green after
   your first push.

---

## Verification Checklist

- [ ] All new files pushed to `main`
- [ ] `NetMonTool_V4.ps1` present and named consistently with the README
- [ ] Actions tab shows PSScriptAnalyzer running (green = errors clean)
- [ ] v4.0.0 tag + release published
- [ ] v3.0.0 tag + release published (or clean start from v4)
- [ ] About section + topics filled in
- [ ] Repo pinned to profile
- [ ] Screenshot added to README

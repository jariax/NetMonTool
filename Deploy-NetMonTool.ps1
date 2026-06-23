# =============================================================
# Deploy-NetMonTool.ps1
# Automates the full GitHub update for NetMonTool V4
#
# Usage:
#   powershell.exe -NoExit -ExecutionPolicy Bypass -File ".\Deploy-NetMonTool.ps1"
# =============================================================

$ErrorActionPreference = "Stop"

# --- CONFIGURATION ---
$GH_USER       = "jariax"
$GH_REPO       = "NetMonTool"
$SOURCE_FOLDER = $PSScriptRoot
$REPO_URL      = "https://github.com/$GH_USER/$GH_REPO.git"
$TEMP_DIR      = Join-Path $env:TEMP "NetMonTool_deploy_$(Get-Random)"

# --- HELPERS ---
function Write-Step {
    param([string]$M)
    Write-Host ""
    Write-Host ">>> $M" -ForegroundColor Cyan
}
function Write-Ok {
    param([string]$M)
    Write-Host "    OK: $M" -ForegroundColor Green
}
function Write-Stop {
    param([string]$M)
    Write-Host ""
    Write-Host "ERROR: $M" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# --- STEP 1: PREREQUISITES ---
Write-Step "Checking prerequisites..."

try {
    $gv = git --version 2>&1
    Write-Ok "Git: $gv"
} catch {
    Write-Stop "Git not found. Install from https://git-scm.com/download/win"
}

try {
    $hv = gh --version 2>&1 | Select-Object -First 1
    Write-Ok "GitHub CLI: $hv"
} catch {
    Write-Stop "GitHub CLI not found. Install from https://cli.github.com then run: gh auth login"
}

Write-Step "Verifying GitHub authentication..."
$authOut = gh auth status 2>&1 | Out-String
if ($authOut -match "Logged in") {
    Write-Ok "Authenticated with GitHub."
} else {
    Write-Stop "Not authenticated. Run: gh auth login"
}

# --- STEP 2: VERIFY SOURCE FILES ---
Write-Step "Verifying source files in: $SOURCE_FOLDER"

$required = @(
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "PSScriptAnalyzerSettings.psd1",
    "NetMonTool_V4.ps1",
    ".gitignore",
    ".github\workflows\lint.yml",
    "docs\ARCHITECTURE.md"
)

$missing = @()
foreach ($f in $required) {
    if (Test-Path (Join-Path $SOURCE_FOLDER $f)) {
        Write-Ok "Found: $f"
    } else {
        $missing += $f
        Write-Host "    MISSING: $f" -ForegroundColor Yellow
    }
}
if ($missing.Count -gt 0) {
    Write-Stop "$($missing.Count) file(s) missing. Put all generated files in: $SOURCE_FOLDER"
}

# --- STEP 3: CLONE ---
Write-Step "Cloning repo into temp folder..."
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
try {
    git clone $REPO_URL $TEMP_DIR 2>&1 | Out-Null
    Write-Ok "Cloned to: $TEMP_DIR"
} catch {
    Write-Stop "Could not clone repo: $_"
}

# --- STEP 4: COPY FILES ---
Write-Step "Copying updated files into repo..."

$flat = @("README.md","CHANGELOG.md","CONTRIBUTING.md","LICENSE","PSScriptAnalyzerSettings.psd1","NetMonTool_V4.ps1",".gitignore")
foreach ($f in $flat) {
    Copy-Item -Path (Join-Path $SOURCE_FOLDER $f) -Destination (Join-Path $TEMP_DIR $f) -Force
    Write-Ok "Copied: $f"
}

$wfDest = Join-Path $TEMP_DIR ".github\workflows"
New-Item -ItemType Directory -Path $wfDest -Force | Out-Null
Copy-Item -Path (Join-Path $SOURCE_FOLDER ".github\workflows\lint.yml") -Destination (Join-Path $wfDest "lint.yml") -Force
Write-Ok "Copied: .github/workflows/lint.yml"

$docsDest = Join-Path $TEMP_DIR "docs"
New-Item -ItemType Directory -Path $docsDest -Force | Out-Null
Copy-Item -Path (Join-Path $SOURCE_FOLDER "docs\ARCHITECTURE.md") -Destination (Join-Path $docsDest "ARCHITECTURE.md") -Force
Write-Ok "Copied: docs/ARCHITECTURE.md"

# --- STEP 5: COMMIT AND PUSH ---
Write-Step "Committing and pushing to main..."
Push-Location $TEMP_DIR
try {
    git add . 2>&1 | Out-Null
    $changed = git status --short 2>&1
    if (-not $changed) {
        Write-Host "    No changes - repo already up to date." -ForegroundColor Yellow
    } else {
        git commit -m "V4: parallel polling, CSV/EventLog reporting, docs, CI linting" 2>&1 | Out-Null
        git push origin main 2>&1 | Out-Null
        Write-Ok "Pushed to main."
    }
} catch {
    Pop-Location
    Write-Stop "Git push failed: $_"
}

# --- STEP 6: v3.0.0 RELEASE ---
Write-Step "Creating v3.0.0 release (retroactive on first commit)..."

$firstHash = (git log --oneline | Select-Object -Last 1) -split " " | Select-Object -First 1
Write-Host "    Tagging first commit ($firstHash) as v3.0.0"

$v3File = Join-Path $env:TEMP "v3notes.md"
$v3Lines = @(
    "## NetMonTool V3.0.0",
    "",
    "Refinement release focused on dashboard readability and PowerShell conventions.",
    "",
    "### Changes",
    "- DEGRADED given its own color (DarkMagenta), visually distinct from WARNING on NOC TV",
    "- Color-coded header summary: status counts render in matching console colors",
    "- Renamed Draw-Dashboard to Write-Dashboard (approved PowerShell verb)",
    "- Fixed N/Ams display bug: AVG10 and JITTER now correctly render N/A"
)
Set-Content -Path $v3File -Value $v3Lines -Encoding UTF8

try {
    $existing = gh release list 2>&1 | Out-String
    if ($existing -match "v3\.0\.0") {
        Write-Host "    v3.0.0 already exists - skipping." -ForegroundColor Yellow
    } else {
        gh release create v3.0.0 --target $firstHash --title "v3.0.0 - Display Clarity and PowerShell Conventions" --notes-file $v3File 2>&1 | Out-Null
        Write-Ok "v3.0.0 release created."
    }
} catch {
    Write-Host "    Warning: could not create v3.0.0 release: $_" -ForegroundColor Yellow
}
Remove-Item $v3File -Force -ErrorAction SilentlyContinue

# --- STEP 7: v4.0.0 RELEASE ---
Write-Step "Creating v4.0.0 release..."

$v4File = Join-Path $env:TEMP "v4notes.md"
$v4Lines = @(
    "## NetMonTool V4.0.0",
    "",
    "Major release: NetMonTool goes from a live dashboard to a complete monitoring",
    "and reporting solution. Still zero-dependency, still a single file.",
    "",
    "### Highlights",
    "- Parallel ping polling: true ~5s refresh regardless of how many nodes are down",
    "- Daily and weekly CSV reporting: availability %, drop %, weighted average latency",
    "- Events CSV: clean incident timeline of every status change",
    "- Windows Event Log integration: events surface in Event Viewer under NOCMonitor",
    "- Live latency chart: optional WinForms graph, one colored line per node",
    "- Zulu (UTC) time standard: single toggle, ideal for secured environments",
    "- Crash-safe and resumable: counters survive a mid-day restart",
    "",
    "### Also in this release",
    "- Full documentation: CHANGELOG, CONTRIBUTING, LICENSE (MIT)",
    "- Architecture deep-dive: docs/ARCHITECTURE.md",
    "- CI: PSScriptAnalyzer linting on every push via GitHub Actions",
    "",
    "### Roadmap",
    "- WARNING and DEGRADED tile color distinction (currently share a slot)",
    "- Approved-verb rename pass planned for V5",
    "",
    "See CHANGELOG.md and docs/ARCHITECTURE.md for full detail."
)
Set-Content -Path $v4File -Value $v4Lines -Encoding UTF8

try {
    $existing = gh release list 2>&1 | Out-String
    if ($existing -match "v4\.0\.0") {
        Write-Host "    v4.0.0 already exists - skipping." -ForegroundColor Yellow
    } else {
        gh release create v4.0.0 --title "v4.0.0 - Reporting Engine and Parallel Polling" --notes-file $v4File --latest 2>&1 | Out-Null
        Write-Ok "v4.0.0 release created and marked as latest."
    }
} catch {
    Write-Host "    Warning: could not create v4.0.0 release: $_" -ForegroundColor Yellow
}
Remove-Item $v4File -Force -ErrorAction SilentlyContinue

# --- STEP 8: REPO METADATA ---
Write-Step "Setting repo description and topics..."
try {
    gh repo edit "$GH_USER/$GH_REPO" --description "Zero-dependency PowerShell NOC dashboard with real-time monitoring, CSV reporting, and Windows Event Log integration." --add-topic "powershell" --add-topic "network-monitoring" --add-topic "noc" --add-topic "dashboard" --add-topic "sysadmin" --add-topic "network-engineering" --add-topic "windows" --add-topic "icmp" --add-topic "monitoring-tool" --add-topic "cybersecurity" 2>&1 | Out-Null
    Write-Ok "Repo description and topics updated."
} catch {
    Write-Host "    Warning: could not update repo metadata: $_" -ForegroundColor Yellow
}

# --- STEP 9: CLEANUP ---
Pop-Location
Write-Step "Cleaning up temp folder..."
Remove-Item -Path $TEMP_DIR -Recurse -Force
Write-Ok "Temp folder removed."

# --- STEP 10: OPEN IN BROWSER ---
Write-Step "Opening your repo in the browser..."
Start-Sleep -Seconds 2
try {
    gh repo view "$GH_USER/$GH_REPO" --web 2>&1 | Out-Null
} catch {
    Write-Host "    Visit manually: https://github.com/$GH_USER/$GH_REPO" -ForegroundColor Cyan
}

# --- DONE ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " DONE. NetMonTool V4 deployed to GitHub." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host " Repo   : https://github.com/$GH_USER/$GH_REPO" -ForegroundColor Cyan
Write-Host " Actions: https://github.com/$GH_USER/$GH_REPO/actions" -ForegroundColor Cyan
Write-Host ""
Write-Host " Next steps:" -ForegroundColor White
Write-Host "   1. Check the Actions tab - lint workflow should be green." -ForegroundColor White
Write-Host "   2. Add a real dashboard screenshot to docs/ and update README." -ForegroundColor White
Write-Host "   3. Pin this repo to your GitHub profile." -ForegroundColor White
Write-Host ""

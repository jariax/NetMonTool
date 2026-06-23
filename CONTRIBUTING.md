# Contributing to NetMonTool

Thanks for your interest in improving NetMonTool. This is a portfolio
project, but it's a real tool used in real NOC-style environments, and
contributions that make it more useful are genuinely welcome.

## Ground Rules

- **Keep it dependency-free.** The core value of this tool is that it runs
  on a stock Windows + PowerShell 5.1 box with no modules to install.
  Please don't introduce external module dependencies in the main script.
- **Single-file portability matters.** The script is designed to be copied
  to air-gapped or locked-down hosts as one `.ps1`. Keep that constraint
  in mind for any structural change.
- **Comment the *why*, not just the *what*.** The existing code explains
  the reasoning behind non-obvious choices (parallel polling, Zulu funnel,
  weighted averages). Match that style.

## Development Setup

1. Fork the repo and clone your fork.
2. Edit the script in any editor (VS Code with the PowerShell extension is
   recommended).
3. Test on a Windows machine with PowerShell 5.1:
   ```powershell
   powershell.exe -NoExit -ExecutionPolicy Bypass -File ".\NetMonTool_V4.ps1"
   ```
4. Use placeholder/public IPs (e.g. `8.8.8.8`, `1.1.1.1`) for testing — never
   commit internal or classified addresses.

## Code Style

- Follow approved PowerShell verbs where practical (`Get-Verb`).
- Use full cmdlet names, not aliases, in committed code.
- Keep functions focused; the script separates ping, state, reporting, and
  display concerns deliberately.

## Linting

This repo runs **PSScriptAnalyzer** on every push and pull request via
GitHub Actions (see `.github/workflows/lint.yml`). Before opening a PR:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path .\NetMonTool_V4.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
```

The build fails only on **Errors**; **Warnings** are surfaced for review but
won't block. Known stylistic warnings (e.g. non-approved verbs) are tracked
in the [CHANGELOG](CHANGELOG.md) roadmap notes.

## Submitting Changes

1. Create a branch: `git checkout -b feature/short-description`
2. Commit with a clear message describing the *why*.
3. Push and open a Pull Request against `main`.
4. Describe what you changed, why, and how you tested it.

## Security

Do not commit real IP addresses, hostnames, share paths, or anything tied to
a production or classified environment. If you find a security issue, please
open a private discussion rather than a public issue.

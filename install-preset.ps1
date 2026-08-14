# install-preset.ps1 — make dsh-subagent-tools available to Web sessions.
#
# WHY THIS IS NEEDED
#   In the `web` profile, agent tools are provided by the mounted agent PRESET
#   (the default `standard` preset composes the `subagent` / `subagent_fork`
#   rows pointing at @deepseek-ai/dsh-tool-subagent), NOT by the host plane.
#   A bundle patch that inserts rows into the host plane is therefore invisible
#   to Web sessions — the stock tools keep loading and this package's per-call
#   overrides never appear. (headless works without this step because its agent
#   uses the host plane directly.)
#
# WHAT THIS SCRIPT DOES
#   1. Copies the deployment's `standard` preset into
#      $DSH_HOME/.agent-presets/standard-plus (user root, writable).
#   2. Rewrites the copy's delegation rows so `tool-subagent` /
#      `tool-subagent-fork` (and the disabled codex/claude-code templates)
#      point at `dsh-subagent-tools` instead of @deepseek-ai/dsh-tool-subagent.
#   3. Switches the default preset in $DSH_HOME/settings.yaml to `standard-plus`
#      so NEW Web sessions use the enhanced tools.
#
# Idempotent: re-running detects an already-adapted copy and skips.
# Uninstall: restore your preset choice in the UI (General > Agent preset) and
#            delete the standard-plus directory, or edit settings.yaml back.
#
# Usage:  powershell -ExecutionPolicy Bypass -File install-preset.ps1
#         then restart `dsh web` and start a NEW session.

$ErrorActionPreference = 'Stop'

# ── locate DSH_HOME (explicit env wins, else default) ────────────────────
$dshHome = $env:DSH_HOME
if (-not $dshHome -or -not (Test-Path $dshHome)) {
  $candidate = Join-Path $PSScriptRoot '..\..\dsh_home'
  if (Test-Path $candidate) { $dshHome = (Resolve-Path $candidate).Path }
}
if (-not $dshHome -or -not (Test-Path $dshHome)) {
  throw "Cannot locate DSH_HOME. Set `$env:DSH_HOME or run from the dsh install tree."
}
Write-Host "[info] DSH_HOME = $dshHome"

# ── find the deployment `standard` preset ────────────────────────────────
$candidates = @(
  (Join-Path $PSScriptRoot '..\..\..\node_modules\@deepseek-ai\dsh\config\agent-presets\standard'),
  (Join-Path $dshHome 'profiles\web\node_modules\@deepseek-ai\dsh\config\agent-presets\standard')
)
$standardDir = $candidates | Where-Object { Test-Path (Join-Path $_ 'agent.cordis.yml') } | Select-Object -First 1
if (-not $standardDir) {
  throw 'Cannot locate the deployment `standard` preset (searched dsh install paths).'
}
Write-Host "[info] standard preset at $standardDir"

$standardFile = Join-Path $standardDir 'agent.cordis.yml'
$presetRoot = Join-Path $dshHome '.agent-presets'
$targetDir = Join-Path $presetRoot 'standard-plus'
$targetFile = Join-Path $targetDir 'agent.cordis.yml'

# ── already adapted? skip ────────────────────────────────────────────────
if (Test-Path $targetFile) {
  $existing = Get-Content $targetFile -Raw
  if ($existing -match "name: 'dsh-subagent-tools'") {
    Write-Host "[skip] standard-plus already adapted."
    exit 0
  }
}

# ── copy standard → standard-plus ────────────────────────────────────────
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
Copy-Item $standardFile $targetFile -Force

# ── rewrite delegation rows to this package ──────────────────────────────
$content = Get-Content $targetFile -Raw
$old = "      name: '@deepseek-ai/dsh-tool-subagent'"
$new = "      name: 'dsh-subagent-tools'"
$count = ([regex]::Matches($content, [regex]::Escape($old))).Count
if ($count -eq 0) {
  throw "No delegation rows to rewrite — anchor '$old' not found in $targetFile. Version mismatch?"
}
$content = $content.Replace($old, $new)
Set-Content -Path $targetFile -Value $content -Encoding UTF8 -NoNewline
Write-Host "[ok] rewrote $count delegation row(s) -> dsh-subagent-tools"

# ── preset.yml metadata ──────────────────────────────────────────────────
$meta = "name: standard-plus`ndescription: standard preset with dsh-subagent-tools delegation tools`n"
Set-Content -Path (Join-Path $targetDir 'preset.yml') -Value $meta -Encoding UTF8 -NoNewline
Write-Host "[ok] wrote preset.yml"

# ── switch default preset in settings.yaml ───────────────────────────────
$settingsPath = Join-Path $dshHome 'settings.yaml'
if (Test-Path $settingsPath) {
  $settings = Get-Content $settingsPath -Raw
  if ($settings -match 'default:\s*standard\s*\n' -or $settings -match 'default:\s*standard$') {
    $settings = [regex]::Replace($settings, 'default:\s*standard(?=\s*$|\s*\n)', 'default: standard-plus')
    Set-Content -Path $settingsPath -Value $settings -Encoding UTF8 -NoNewline
    Write-Host "[ok] settings.yaml default preset -> standard-plus"
  } elseif ($settings -match 'default:\s*standard-plus') {
    Write-Host "[skip] settings.yaml already default standard-plus"
  } else {
    Write-Host "[warn] settings.yaml has no `default: standard` anchor; set the preset manually in the UI (General > Agent preset)."
  }
} else {
  Write-Host "[warn] no settings.yaml found; default preset stays standard — set standard-plus in the UI (General > Agent preset)."
}

Write-Host ''
Write-Host 'Done. Restart `dsh web` and start a NEW session for the enhanced subagent tools to appear.'

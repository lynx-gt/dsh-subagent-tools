# dsh-subagent-tools

Enhanced subagent delegation tools for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (dsh):
**per-call model / provider / persona / toolFilter overrides**, **`@preset:` persona references**, and
**`provider/model` composite model ids** — shipped as a standard **bundle** that patches **no official
package file**.

| [English](README.md) | [中文](README.zh.md) |

## What it adds

The stock `subagent` / `subagent_fork` tools only accept `description`, `prompt`, and `run_in_background`.
This plugin replaces them with the same surface plus per-call overrides:

| Parameter | Effect |
|---|---|
| `model` | Override the child's LLM model for this call. Accepts a bare id (`k3`) or a composite (`kimi-code/k3`) that also switches the provider. |
| `provider` | Override the delegation provider for this call (`spawn` / `fork` / ...). |
| `persona` | Override the child's persona for this call — raw text, or `@preset:<id>` to load a saved agent preset's persona (by display name or directory id). |
| `toolFilter` | Override the child's tool allow/deny filter for this call. |

All overrides default to the instance configuration, so a bare install behaves exactly like the stock tools.

## Installation

```sh
dsh plugin --profile web add dsh-subagent-tools          # npm
# or: dsh plugin --profile web add github:lynx-gt/dsh-subagent-tools#main
# or: dsh plugin --profile web add ./dsh-subagent-tools  # local checkout
```

Restart `dsh --profile web`.

### Web sessions: also run the preset adapter (important)

In the **web** profile, agent tools are provided by the mounted agent **preset**
(the default `standard` preset composes `subagent` / `subagent_fork` pointing at
`@deepseek-ai/dsh-tool-subagent`), **not** by the host plane. A bundle patch that
disables the stock rows and inserts its own is invisible to Web sessions — the
stock tools keep loading and this package's per-call overrides never appear
(headless works without this step).

Run the preset adapter to make Web sessions use this package:

```sh
powershell -ExecutionPolicy Bypass -File install-preset.ps1   # Windows
# or: ./install-preset.sh                                     # POSIX
```

It copies the `standard` preset into `$DSH_HOME/.agent-presets/standard-plus`,
rewrites its `tool-subagent` / `tool-subagent-fork` rows to point at this
package, and switches the default preset. Then **restart `dsh web` and start a
NEW session** (presets are read at session creation and cannot be switched in a
live session). To revert: pick `standard` again in the UI (General > Agent
preset) and delete the `standard-plus` directory.

> `headless` and other non-web profiles do not need this step.

### Telling the model which presets exist (`presetHints`)

The `persona` parameter accepts `@preset:<id>` references, but the tool schema
does not list which presets exist on your deployment. Set `presetHints` on the
tool rows (see `cordis.patch.yml`) to surface them in the schema — the model
then sees "Available presets on this deployment: @preset:翻译员, ..." and can
pick one itself. Omit the key to stay generic (presets differ per machine).

### Compatibility

Declares `peerDependencies` on the public dsh packages (`^0.1.0-rc.6`). If your dsh version moves out of
the compatible range, pnpm reports a peer conflict and the plugin refuses to load — bump this package
instead of running on a silently broken API.

## Verified

Tested against a stock dsh `0.1.0-rc.6` install (no local patches) on Windows via
headless and web profiles:

- per-call `model="kimi-code/k3"` composite routing ✅
- per-call `provider="fork"` and raw-text `persona` ✅
- `@preset:` by display name (`@preset:审校员`) and directory id (`@preset:translation-reviewer`) ✅
- `presetHints` schema injection ✅
- Web profile: the preset adapter (`install-preset.ps1`) makes Web sessions use
  this bundle's tools (verified with the 5 presets above in a live web session)

## Example

```
Delegate a task to a subagent using model kimi-code/k3 with the reviewer persona:
  subagent(description="Review the translation", prompt="...", model="kimi-code/k3", persona="@preset:审校员")
```

## Design

- **A bundle, not a patched install.** This package is a standard dsh **bundle**
  (`dsh.bundle` manifest + `cordis.patch.yml`): it disables the shipped
  `tool-subagent` / `tool-subagent-fork` rows and inserts its own. **No official
  package file is patched** — nothing in the dsh installation is modified.
- **Independent implementation.** The tool is written against the public dsh API
  (`defineTool`, `ctx.subagents.start` / `startContinuable`, `settleRun`), not a fork of the official source.
- **Upgrades.** The bundle lives in the profile's own `node_modules` (pnpm
  symlink), so a dsh upgrade does not remove it. But dsh is in developer preview
  (rc.6): if an upgrade changes the public API, `peerDependencies` makes the
  plugin refuse to load instead of failing silently — bump this package then.
- **No `cwd` parameter here.** Per-call working-directory control needs two
  small patches in the dsh installation's in-process subagent providers
  (foreground + continuable child creation). That lives in the companion
  package **`dsh-subagent-tools-cwd`**, which bundles this plugin's
  functionality **plus** the `cwd` parameter **plus** the required patches.
  Install one or the other — not both.

## Limitations

- **`@preset:` depends on the local preset layout.** `$DSH_HOME/.agent-presets`
  is where dsh stores user-authored presets; the path is not a hard public
  contract, so a future dsh release could change discovery. Presets also differ
  per machine — an `@preset:翻译员` reference only works where that preset exists.
- **Web sessions need the preset adapter.** The `standard` preset that ships
  with dsh still points its delegation rows at the official package; until you
  run `install-preset.ps1` / `install-preset.sh`, Web sessions keep the stock
  tools (headless and other non-web profiles use this bundle directly).
- **`provider` means the subagent backend**, not an LLM provider. To route a
  child to a different LLM provider use the composite `model` id
  (`kimi-code/k3`) or the instance `agentOptions`.

## License

MIT

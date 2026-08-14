#!/usr/bin/env bash
# install-preset.sh — make dsh-subagent-tools available to Web sessions.
#
# WHY THIS IS NEEDED
#   In the `web` profile, agent tools are provided by the mounted agent PRESET
#   (the default `standard` preset composes the `subagent` / `subagent_fork`
#   rows pointing at @deepseek-ai/dsh-tool-subagent), NOT by the host plane.
#   A bundle patch that inserts rows into the host plane is invisible to Web
#   sessions. This script copies `standard` to a user preset (`standard-plus`),
#   rewrites its delegation rows to point at `dsh-subagent-tools`, and switches
#   the default preset.
#
# Usage:  ./install-preset.sh
#         then restart `dsh web` and start a NEW session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DSH_HOME="${DSH_HOME:-}"
if [[ -z "$DSH_HOME" || ! -d "$DSH_HOME" ]]; then
  for c in "$SCRIPT_DIR/../../dsh_home" "$SCRIPT_DIR/../../../dsh_home"; do
    if [[ -d "$c" ]]; then DSH_HOME="$(cd "$c" && pwd)"; break; fi
  done
fi
if [[ -z "$DSH_HOME" || ! -d "$DSH_HOME" ]]; then
  echo "[ERROR] Cannot locate DSH_HOME. Set \$DSH_HOME or run from the dsh install tree." >&2
  exit 1
fi
echo "[info] DSH_HOME = $DSH_HOME"

STANDARD=""
for c in "$SCRIPT_DIR/../../../node_modules/@deepseek-ai/dsh/config/agent-presets/standard" \
         "$DSH_HOME/profiles/web/node_modules/@deepseek-ai/dsh/config/agent-presets/standard"; do
  if [[ -f "$c/agent.cordis.yml" ]]; then STANDARD="$c"; break; fi
done
if [[ -z "$STANDARD" ]]; then
  echo "[ERROR] Cannot locate the deployment \`standard\` preset." >&2
  exit 1
fi
echo "[info] standard preset at $STANDARD"

PRESET_ROOT="$DSH_HOME/.agent-presets"
TARGET_DIR="$PRESET_ROOT/standard-plus"
TARGET_FILE="$TARGET_DIR/agent.cordis.yml"
mkdir -p "$TARGET_DIR"

if [[ -f "$TARGET_FILE" ]] && grep -qF "name: 'dsh-subagent-tools'" "$TARGET_FILE"; then
  echo "[skip] standard-plus already adapted."
  exit 0
fi

cp "$STANDARD/agent.cordis.yml" "$TARGET_FILE"
python3 - "$TARGET_FILE" <<'PY'
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
old = "      name: '@deepseek-ai/dsh-tool-subagent'"
new = "      name: 'dsh-subagent-tools'"
count = content.count(old)
if count == 0:
    print(f'[ERROR] no delegation rows to rewrite in {path}', file=sys.stderr)
    sys.exit(1)
content = content.replace(old, new)
with open(path, 'w', encoding='utf-8', newline='') as f:
    f.write(content)
print(f'[ok] rewrote {count} delegation row(s) -> dsh-subagent-tools')
PY

printf 'name: standard-plus\ndescription: standard preset with dsh-subagent-tools delegation tools\n' \
  > "$TARGET_DIR/preset.yml"
echo "[ok] wrote preset.yml"

SETTINGS="$DSH_HOME/settings.yaml"
if [[ -f "$SETTINGS" ]]; then
  if grep -qE 'default:[[:space:]]*standard([[:space:]]*$)' "$SETTINGS"; then
    python3 - "$SETTINGS" <<'PY'
import sys, re
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
content = re.sub(r'default:[ \t]*standard([ \t]*$)', r'default: standard-plus\1', content, flags=re.M)
with open(path, 'w', encoding='utf-8', newline='') as f:
    f.write(content)
print('[ok] settings.yaml default preset -> standard-plus')
PY
  elif grep -q 'default: standard-plus' "$SETTINGS"; then
    echo "[skip] settings.yaml already default standard-plus"
  else
    echo "[warn] no \`default: standard\` anchor in settings.yaml; set standard-plus in the UI (General > Agent preset)."
  fi
else
  echo "[warn] no settings.yaml found; set standard-plus in the UI (General > Agent preset)."
fi

echo ""
echo "Done. Restart \`dsh web\` and start a NEW session for the enhanced subagent tools to appear."

#!/usr/bin/env bash
#
# QA Skills installer
# Usage:
#   ./install.sh             # global install (~/.claude/skills/)
#   ./install.sh --project   # project install (.claude/skills/ in cwd)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=("qa-bundle-generator" "qa-test-executor")

if [[ "${1:-}" == "--project" ]]; then
  TARGET=".claude/skills"
  SCOPE="project (.claude/skills/)"
else
  TARGET="$HOME/.claude/skills"
  SCOPE="global (~/.claude/skills/)"
fi

echo "Installing QA skills to: $SCOPE"
mkdir -p "$TARGET"

for skill in "${SKILLS[@]}"; do
  src="$SCRIPT_DIR/$skill"
  dst="$TARGET/$skill"
  if [[ ! -d "$src" ]]; then
    echo "  [skip] $skill (not found in bundle)" >&2
    continue
  fi
  if [[ -d "$dst" ]]; then
    echo "  [overwrite] $skill"
  else
    echo "  [install]   $skill"
  fi
  rm -rf "$dst"
  cp -r "$src" "$dst"
done

echo ""
echo "Done. Invoke with:"
echo "  /qa-bundle-generator <JIRA-KEY>"
echo "  /qa-test-executor <TC-KEY or JIRA-KEY>"

#!/usr/bin/env bash
# OpenHands PreToolUse hook for the `infinite` skill (thin dispatcher).
#
# Stops the agent from disabling its own enforcement: running the guard, the
# installer, or the hooks; editing .openhands/guard or .openhands/hooks.json.
#
#   exit 0  allow the tool call
#   exit 2  deny the tool call
#
# A no-op when enforcement is not installed in the project, so it is safe to
# install globally.

set -uo pipefail

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
input="$(cat 2>/dev/null || true)"

guard=""
for candidate in "$hook_dir/infinite_guard.py" "$hook_dir/../guard/infinite_guard.py"; do
    if [ -f "$candidate" ]; then
        guard="$candidate"
        break
    fi
done

if [ -z "$guard" ] || ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

printf '%s' "$input" | python3 "$guard" pretool
exit $?

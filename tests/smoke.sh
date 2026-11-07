#!/usr/bin/env bash
# Smoke + adversarial tests for the `infinite` skill. bash + python3 only.
#
#   tests/smoke.sh
#
# The second half is the important half: it tries to disable enforcement the way
# an agent would, and asserts that every attempt fails closed.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/infinite" && pwd)"
S="$SKILL_DIR/scripts"
STATE="$S/infinite_state.py"
GUARD="$S/infinite_guard.py"
INSTALL="$S/install-openhands-hooks.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }
check() { if [ "$1" = "$2" ]; then pass "$3 ($1)"; else fail "$3 (got $1, want $2)"; fi; }

# --- helpers ---------------------------------------------------------------- #
stop_event() { printf '{"event_type":"Stop","working_dir":"%s"}' "$1"; }
pretool_event() { printf '{"event_type":"PreToolUse","working_dir":"%s","tool_name":"%s","tool_input":%s}' "$1" "$2" "$3"; }
prompt_event() { printf '{"event_type":"UserPromptSubmit","working_dir":"%s","message":"%s"}' "$1" "$2"; }

stop_code() { # project policy
    stop_event "$1" | OPENHANDS_PROJECT_DIR="$1" bash "$1/.openhands/hooks/infinite-stop.sh" --policy "$2" >/dev/null 2>&1
    echo $?
}
pretool_code() { # project tool json
    pretool_event "$1" "$2" "$3" | OPENHANDS_PROJECT_DIR="$1" bash "$1/.openhands/hooks/infinite-pretool.sh" >/dev/null 2>&1
    echo $?
}
prompt() { prompt_event "$1" "$2" | OPENHANDS_PROJECT_DIR="$1" bash "$1/.openhands/hooks/infinite-userprompt.sh" >/dev/null 2>&1; }

policy_of() {
    python3 - "$1/.openhands/hooks.json" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
for entry in config["stop"]:
    for hook in entry["hooks"]:
        if "--policy" in hook["command"]:
            print(hook["command"].split("--policy ")[1].strip())
            raise SystemExit
raise SystemExit("no policy in hooks.json")
PY
}

echo "== package shape =="
python3 - "$SKILL_DIR/SKILL.md" <<'PY' || FAILED=1
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert match, "SKILL.md must start with frontmatter"
front = match.group(1)
assert re.search(r"^name: infinite$", front, re.M), "name must be 'infinite'"
assert re.search(r"^description:", front, re.M), "description required"
assert re.search(r"^triggers:", front, re.M), "triggers required"
print("  ok   frontmatter valid")
PY
[ "$(basename "$SKILL_DIR")" = "infinite" ] && pass "directory name matches skill name" || fail "directory name"

echo "== ledger helper =="
PROJ="$WORK/proj"
mkdir -p "$PROJ"
python3 "$STATE" --dir "$PROJ" init --task "smoke task" >/dev/null || fail "init"
python3 "$STATE" --dir "$PROJ" log --target "t" --verification "v" --next "n" >/dev/null || fail "log"
grep -q "round     : 1" < <(python3 "$STATE" --dir "$PROJ" status) && pass "log increments round" || fail "round increment"
python3 "$STATE" --dir "$PROJ" report | grep -q "| 1 |" && pass "report renders ledger" || fail "report"

echo "== installer =="
"$INSTALL" --dir "$PROJ" --gate "tests:test -f ok.txt" --gate "lint:true" >/dev/null 2>&1 || fail "install"
for f in .openhands/guard/infinite_guard.py .openhands/hooks/infinite-stop.sh \
         .openhands/hooks/infinite-pretool.sh .openhands/hooks/infinite-userprompt.sh \
         .openhands/hooks.json; do
    [ -e "$PROJ/$f" ] && pass "installed $f" || fail "missing $f"
done
POLICY="$(policy_of "$PROJ")"
[ -n "$POLICY" ] && pass "policy embedded in hook command" || fail "no embedded policy"

BEFORE="$(cat "$PROJ/.openhands/hooks.json")"
"$INSTALL" --dir "$PROJ" --gate "lint:true" >/dev/null 2>&1
COUNT="$(python3 -c "import json;print(len(json.load(open('$PROJ/.openhands/hooks.json'))['stop']))")"
check "$COUNT" "1" "installer is idempotent"

echo "== stop gate: the task being done is not a stop condition =="
check "$(stop_code "$PROJ" "$POLICY")" "2" "failing gate denies finish"
touch "$PROJ/ok.txt"
check "$(stop_code "$PROJ" "$POLICY")" "2" "no verified round denies finish"
python3 "$STATE" --dir "$PROJ" log --target "ok.txt" --verification "pass" --next "more" >/dev/null
check "$(stop_code "$PROJ" "$POLICY")" "2" "mode=required denies even after a clean round"
check "$(stop_code "$PROJ" "$POLICY")" "2" "repeated attempts stay denied"

echo "== the agent cannot disable its own enforcement =="
AGENT_ATTACKS=(
    '{"command":"python3 .openhands/guard/infinite_guard.py disarm"}'
    '{"command":"rm -rf .openhands"}'
    '{"command":"rm -rf .openhands/guard"}'
    '{"command":"bash skills/infinite/scripts/install-openhands-hooks.sh --uninstall"}'
    '{"command":"sed -i s/stop// .openhands/hooks.json"}'
    '{"command":"python3 -c open(\".openhands/hooks.json\",\"w\").write(\"{}\")"}'
    '{"command":"cat .openhands/guard/config.json"}'
    '{"path":".openhands/hooks.json"}'
    '{"path":".openhands/guard/config.json"}'
)
for attack in "${AGENT_ATTACKS[@]}"; do
    check "$(pretool_code "$PROJ" terminal "$attack")" "2" "blocked: $attack"
done

echo "== ordinary work is not blocked =="
check "$(pretool_code "$PROJ" terminal '{"command":"pytest -q"}')" "0" "test run allowed"
check "$(pretool_code "$PROJ" terminal '{"command":"git commit -am round-3"}')" "0" "commit allowed"
check "$(pretool_code "$PROJ" file_editor '{"path":"README.md","command":"str_replace"}')" "0" "doc edit allowed"
check "$(pretool_code "$PROJ" file_editor \
    '{"path":"docs/infinite.md","command":"create","file_text":"mentions .openhands/guard"}')" \
    "0" "prose mentioning the guard allowed"

echo "== tampering with state on disk does not disarm =="
echo '{"mode":"disabled","gates":[]}' > "$PROJ/.openhands/guard/config.json"
check "$(stop_code "$PROJ" "$POLICY")" "2" "rewritten config ignored (policy is in the hook)"
rm -f "$PROJ/.openhands/guard/config.json"
check "$(stop_code "$PROJ" "$POLICY")" "2" "deleted config fails closed"
printf '{"working_dir":"%s"}' "$PROJ" | OPENHANDS_PROJECT_DIR="$PROJ" \
    bash "$PROJ/.openhands/hooks/infinite-stop.sh" --policy "corrupted" >/dev/null 2>&1
check "$?" "2" "corrupted policy fails closed"
rm -rf "$PROJ/.openhands/guard"
stop_event "$PROJ" | OPENHANDS_PROJECT_DIR="$PROJ" \
    bash "$PROJ/.openhands/hooks/infinite-stop.sh" --policy "$POLICY" >/dev/null 2>&1
check "$?" "2" "deleting .openhands/guard does not disarm (second copy by the hooks)"

echo "== only the user ends infinite mode =="
prompt "$PROJ" "add a stop button to the UI"
check "$(stop_code "$PROJ" "$POLICY")" "2" "prose about a 'stop button' does not disarm"
prompt "$PROJ" "how does the stop hook work?"
check "$(stop_code "$PROJ" "$POLICY")" "2" "question about stopping does not disarm"
prompt "$PROJ" "stop"
check "$(stop_code "$PROJ" "$POLICY")" "0" "user says 'stop' -> finish allowed"
prompt "$PROJ" "/infinite continue"
check "$(stop_code "$PROJ" "$POLICY")" "2" "user says '/infinite' -> armed again"
"$INSTALL" --dir "$PROJ" --disarm >/dev/null 2>&1
check "$(stop_code "$PROJ" "$POLICY")" "0" "installer --disarm allows finish"
"$INSTALL" --dir "$PROJ" --uninstall >/dev/null 2>&1
grep -q "infinite" "$PROJ/.openhands/hooks.json" && fail "uninstall left hook entries" || pass "uninstall removes hook entries"

echo
if [ "$FAILED" -eq 0 ]; then echo "all tests passed"; else echo "FAILURES PRESENT" >&2; fi
exit "$FAILED"

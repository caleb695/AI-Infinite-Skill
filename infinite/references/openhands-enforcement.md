# Enforcement in OpenHands — the agent does not get to decide

Prompting is advisory: the model can end a run anyway. This document describes
the part of the skill that is not advisory. Three hooks and a policy the agent
cannot change decide whether a run may finish.

| Layer | Mechanism | Who controls it |
| --- | --- | --- |
| Instructions | [`SKILL.md`](../SKILL.md) | Prompt — advisory, may be ignored |
| **Enforcement** | `Stop` hook → `infinite_guard.py` (exit 2 = deny) | **The user** |
| **Self-protection** | `PreToolUse` hook blocks editing/running enforcement | **The user** |
| **Exit control** | `UserPromptSubmit` hook: only a real user message can arm/disarm | **The user** |
| Progress record | `.infinite/ledger.jsonl` | The agent (auditable) |

## Install

```bash
bash infinite/scripts/install-openhands-hooks.sh --dir /path/to/project
```

Add `--install-skill` to also place the skill at `.agents/skills/infinite/`
(`--scope user` for `~/.agents/skills/`).

That single command:

1. copies the guard to `.openhands/guard/infinite_guard.py` **and**
   `.openhands/hooks/infinite_guard.py` (two copies, so deleting one directory
   cannot disable enforcement);
2. copies three thin hook scripts into `.openhands/hooks/`;
3. **embeds the policy** — mode, gates, required rounds — as a base64 blob in the
   Stop hook command inside `.openhands/hooks.json`;
4. preserves any existing hook entries and never duplicates its own.

```json
{
  "stop": [
    { "matcher": "*", "hooks": [
      { "command": "bash .openhands/hooks/infinite-stop.sh --policy eyJ2IjoyLCJtb2RlIjoicmVxdWlyZWQi...", "timeout": 60 }
    ]}
  ],
  "pre_tool_use": [
    { "matcher": "*", "hooks": [{ "command": "bash .openhands/hooks/infinite-pretool.sh", "timeout": 20 }] }
  ],
  "user_prompt_submit": [
    { "matcher": "*", "hooks": [{ "command": "bash .openhands/hooks/infinite-userprompt.sh", "timeout": 15 }] }
  ]
}
```

### Why the policy is in the hook command

The agent has shell access and can rewrite any file in the repository. What it
cannot do is change the hook command of the **running** conversation: OpenHands
loads `hooks.json` when the conversation starts. So the policy travels on the
command line, and the on-disk `config.json` is only a mirror for `status`.

The Stop hook forwards `"$@"` (the policy) to the guard. If the policy argument
is present but unreadable, the guard **fails closed** — it never falls back to a
file the agent could have written.

## The three hooks

### `stop` — the finish gate

Every finish attempt runs the gates and checks the ledger, then denies with
`exit 2` and a reason the agent must act on:

```
Infinite mode is ON (required). Finishing is blocked because 2 gate(s) fail.
Fix them, log the round, and continue.
Gates: tests: FAIL (exit 1) --- tests output --- <last 12 lines>; lint: PASS (exit 0)
Rounds logged: 12 (8 since arming). Last round: 12 - target: quoting - verification recorded: yes.
```

The deny payload also carries `additionalContext` with the loop protocol, so the
next turn restarts the loop instead of arguing about it.

Repeated finish attempts with no new verified round get a sharper message
(`... you attempted to finish again without completing a new round`) and are
counted in `.openhands/guard/attempts.json`.

Modes (`--mode`):

| Mode | Allows a finish when |
| --- | --- |
| `required` (default) | Never. Each finish attempt becomes the next round |
| `allow-when-green` | Every gate passes **and** a newly verified round was logged |
| `always` | Never, and gates are not evaluated (cheapest) |
| `disabled` | Installed but off |

### `pre_tool_use` — the agent cannot switch it off

Denied outright:

- running the guard, the installer, or any hook (`disarm`, `--uninstall`, ...);
- `rm`, `mv`, `sed -i`, `chmod`, `tee`, `>` and friends aimed at `.openhands`
  or any `infinite*` file;
- reading `.openhands/guard` state;
- editing `.openhands/hooks.json` or the guard through a file tool.

Still allowed: tests, builds, commits, ordinary file edits, and documentation
that merely *mentions* these paths (the rule is path-based for file tools,
text-based only for shell tools). Denials are logged to `events.jsonl`.

### `user_prompt_submit` — only the user can end it

A real user message is the one input the agent cannot forge. It disarms on a
stop phrase and re-arms on an infinite phrase.

- **Disarms:** `stop`, `halt`, `cancel`, `quit`, `that's enough`, `/stop`,
  short imperative messages like "ok stop now".
- **Arms:** `/infinite`, `/forever`, `/never-stop`, "never stop", "keep going",
  "infinite mode", "until I say stop".
- **Ignored:** prose and questions — "add a stop button to the UI", "how does the
  stop hook work?", "why did the build stop?" — so normal work does not
  accidentally end the loop.

## Ending it (the user's commands)

```bash
# in the conversation
stop

# or from your own terminal
bash infinite/scripts/install-openhands-hooks.sh --dir . --disarm
bash infinite/scripts/install-openhands-hooks.sh --dir . --uninstall
```

Both self-heal: even if the agent deleted the guard directory, these commands
restore it and then honour your request. That is deliberate — the user must
always be able to stop the loop, no matter what state the repository is in.

## Verify it yourself

```bash
scripts/install-openhands-hooks.sh --dir . --status   # mode, gates, rounds, attempts, last decisions
.openhands/guard/infinite_guard.py doctor --dir .     # run the gates now
```

Manual hook test without a conversation:

```bash
echo '{"event_type":"Stop","working_dir":"'"$PWD"'"}' \
  | OPENHANDS_PROJECT_DIR="$PWD" bash .openhands/hooks/infinite-stop.sh --policy "$POLICY"; echo "exit=$?"
```

`tests/smoke.sh` automates all of this, including nine attack attempts.

## What enforcement still cannot do

- **A deleted hook script stops the hook from running.** OpenHands treats a hook
  that errors as an error, not a denial. Enforcement cannot survive an agent that
  removes every copy and restarts the conversation; that is why the backup copy
  lives beside the hooks and why `--status` reports `last decisions`.
- **Iteration ceiling.** A run still ends at `max_iterations` (default 500). The
  ledger makes the boundary resumable; raise the limit for longer runs.
- **Stuck detection.** Identical repeated actions trip it. The loop protocol
  forbids repeating a failing command, and the deny payload always names the next
  target.
- **A user who kills the process** outranks any hook. "Never stop" means the
  agent never *elects* to stop.

## Safety

- Arm only when the user asked for an infinite loop.
- The deny payloads never contain secrets; gate output is truncated to 12 lines.
- `--uninstall` leaves unrelated hooks untouched.
- Never commit `.openhands/guard` state; see
  [`assets/project.gitignore.fragment`](../assets/project.gitignore.fragment).

## See also

- Hooks reference: <https://docs.openhands.dev/openhands/usage/customization/hooks>
- Skills overview: <https://docs.openhands.dev/overview/skills>
- Agent Skills format: <https://docs.openhands.dev/sdk/guides/skill>

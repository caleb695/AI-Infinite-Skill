# infinite

An agent skill that never lets the agent finish. When the task is complete it
starts another round: audit the current state, find the single weakest part,
improve it, verify it, log it, and go again. The loop ends only when the user
explicitly says stop.

> "Go back, improve, go back, improve" — the default behaviour, not a fallback.

## Trigger

`/infinite`, `/forever`, `/never-stop`, or any of: "never stop", "don't stop
until I say stop", "keep going", "keep improving", "infinite mode", "work
forever", "until I say stop".

## What it does each round

1. **Check for stop** — re-read the latest user message; continue unless it
   clearly means stop.
2. **Snapshot** — re-run the project's checks and read the current diff.
3. **Audit** — pick the weakest part, scored by impact × confidence ÷ effort.
4. **Improve** — one meaningful change, with a test that would have caught it.
5. **Verify** — the targeted check plus the full suite.
6. **Log and report** — append to `.infinite/ledger.jsonl`, post one short line,
   go to 1.

## Why it does not drift or die

- **Explicit stop definition** — only user-authored stop language ends the loop;
  silence, approvals, new questions, and tool failures never do.
- **Durable ledger** — round history lives on disk, so context compaction or a
  new session resumes at the next round instead of restarting.
- **Escalation ladder** — as easy wins run out, rounds climb from fix → prove →
  harden → simplify → extend, so quality keeps rising instead of re-polishing.
- **No fake progress** — a round that found nothing must say so and change axis.
- **Enforcement, not suggestion** — three OpenHands hooks make finishing deny,
  block the agent from disabling them, and let only a real user message end the
  mode. The policy travels on the hook command line, which the running
  conversation cannot rewrite.

## Install

Copy the directory into a skills location OpenHands reads:

```bash
# per project (recommended)
mkdir -p .agents/skills
cp -r skills/infinite .agents/skills/infinite

# or per user, for every project
mkdir -p ~/.agents/skills
cp -r skills/infinite ~/.agents/skills/infinite
```

Legacy locations `.openhands/skills/` and `.openhands/microagents/` also work.
Claude Code reads the same `SKILL.md` from `.claude/skills/`.

### Turn it into enforcement (OpenHands)

```bash
.agents/skills/infinite/scripts/install-openhands-hooks.sh --dir .
```

One command installs the guard, three hooks, and an immutable per-session
policy. From then on:

- every finish attempt is **denied** (exit 2) with the failing gates and the
  next target in the deny reason;
- the agent **cannot** run the guard, edit it, rewrite `hooks.json`, or delete
  enforcement — `PreToolUse` blocks it;
- only a **real user message** ends the mode (`stop`), and prose like "add a stop
  button to the UI" does not.

```bash
scripts/install-openhands-hooks.sh --dir . --status    # mode, gates, rounds, attempts
scripts/install-openhands-hooks.sh --dir . --disarm    # user says stop
scripts/install-openhands-hooks.sh --dir . --uninstall # remove it all
```

## Usage

```
/infinite make the CSV exporter production-ready
```

Then leave it running. Say `stop` (or `/stop`) to end it. Say `stop after the
tests pass` to end at a boundary. Say `continue` later to resume from the ledger.

## Contents

```
infinite/
├── SKILL.md                          the loop contract and round procedure
├── commands/infinite.md              slash-command shim
├── references/
│   ├── loop-protocol.md              ledger, checkpointing, resume, stop handling
│   ├── audit-playbook.md             per-domain audit checklists, scoring, ladder
│   └── openhands-enforcement.md      Stop hook setup, arming, safety, limits
├── scripts/
│   ├── infinite_guard.py            enforcement engine (stop/pretool/userprompt)
│   ├── stop_hook.sh                 Stop hook dispatcher (forwards the policy)
│   ├── pretool_hook.sh             blocks the agent from disabling enforcement
│   ├── userprompt_hook.sh          arms/disarms only on real user messages
│   ├── infinite_state.py            ledger/status/report (stdlib only)
│   └── install-openhands-hooks.sh   user control surface: install/arm/disarm
├── assets/                           templates copied into a project if needed
└── .plugin/, .claude-plugin/, .codex-plugin/   plugin metadata
```

## Requirements

- An agent that reads Agent Skills `SKILL.md` files (OpenHands, Claude Code, or
  any compatible client).
- `python3` for the state helper; `bash` for the hook. Both are optional — the
  skill degrades to plain instructions without them.

## Limits, honestly

- Enforcement lives in hooks, so it applies to OpenHands (Agent Canvas, Cloud,
  CLI, SDK). Other clients get the instructions only.
- A deleted hook script stops the hook from running — OpenHands treats an
  erroring hook as an error, not a denial. Two guard copies and `--status`
  ("last decisions") are the mitigation, not a guarantee against an agent that
  removes every copy and restarts the conversation.
- OpenHands still ends a *run* at `max_iterations` (default 500) and applies
  stuck detection; the ledger makes that boundary resumable rather than fatal.
- Nothing can override a user who stops the process, closes the session, or
  revokes access. "Never stop" means the agent never elects to stop.

## License

MIT

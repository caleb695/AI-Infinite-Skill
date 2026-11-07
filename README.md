# AI-Infinite-Skill

An agent skill that refuses to finish.

When the task is done, it does not stop — it goes back, finds the weakest part,
improves it, verifies the improvement, and starts another round. Forever. The
loop ends only when the user explicitly says stop.

Built to the [Agent Skills](https://docs.openhands.dev/overview/skills)
`SKILL.md` standard, so it works with **OpenHands** (Agent Canvas, Cloud, CLI,
SDK), Claude Code, and any other client that reads skills — with extra
harness-level enforcement available on OpenHands.

```
round 1: complete the task
round 2: audit → fix the weakest part → verify
round 3: audit → harden the edge case → verify
round 4: audit → add the missing test → verify
... until the user says stop
```

## Why this exists

Agents stop early. They finish the obvious version of a task, write "done", and
hand back something that is correct-ish, tested-ish, and polished-ish. The work
that makes software or writing actually good — the second pass, the edge case,
the hostile input, the test that was missing — never happens unless someone asks
for it.

This skill makes that second pass the default, and then the third, and the
fourth.

## What it does each round

| Step | Action |
| --- | --- |
| 1 | **Check for stop** — re-read the latest user message; continue unless it explicitly means stop |
| 2 | **Snapshot** — re-run the project's checks, read the current diff, note open debt |
| 3 | **Audit** — pick the single weakest part, scored `impact × confidence ÷ effort` |
| 4 | **Improve** — one meaningful change, plus the test that would have caught it |
| 5 | **Verify** — the targeted check *and* the full suite |
| 6 | **Log and report** — append to the ledger, post one short line, go to step 1 |

The round is small on purpose: a user's "stop" lands within seconds to a few
minutes, never after an hour of unbounded work.

## Install

### OpenHands

Skills are read from these locations, in order of precedence:

```bash
# per project (recommended)
mkdir -p .agents/skills
cp -r skills/infinite .agents/skills/infinite

# or per user, for every conversation
mkdir -p ~/.agents/skills
cp -r skills/infinite ~/.agents/skills/infinite
```

Legacy `.openhands/skills/` and `.openhands/microagents/` directories are still
supported by OpenHands and work too.

### Claude Code or another Agent Skills client

```bash
mkdir -p .claude/skills
cp -r skills/infinite .claude/skills/infinite
```

## Use it

```
/infinite make the CSV exporter production-ready
```

or just say it in plain language:

```
Keep improving this API until I say stop.
```

Other triggers: `never stop`, `don't stop`, `keep going`, `keep improving`,
`infinite mode`, `work forever`, `until I say stop`, `/forever`, `/never-stop`.

**To end the loop**, say `stop`, `cancel`, `that's enough`, or `/stop`. Qualified
stops work too: `stop after the tests pass`. Silence is never a stop signal, and
neither is approval, a new question, a tool failure, or the agent deciding it is
done.

Resume later with `continue` — it picks up at the next round from the ledger
rather than starting over.

## Optional: make finishing impossible

Prompt rules are usually enough, but OpenHands [hooks](https://docs.openhands.dev/openhands/usage/customization/hooks)
can enforce the loop at the harness level:

```bash
# 1. install a Stop hook that denies "finish" while the loop is armed
.agents/skills/infinite/scripts/install-openhands-hooks.sh --dir .

# 2. arm the loop
python3 .agents/skills/infinite/scripts/infinite_state.py arm
```

While `.infinite/ARMED` exists, every attempt to finish returns:

```json
{
  "decision": "deny",
  "reason": "Infinite mode is ARMED (round 7, next target: ...). Finishing is not allowed: the user has not said stop. Start round 8 now — ...",
  "additionalContext": "Infinite loop protocol: (1) re-read the latest user message ..."
}
```

The hook does not just block — it restarts the loop with the current round number
and next target injected into the agent's context.

Disarm the moment the user says stop (always *before* writing the final summary,
otherwise the agent cannot finish the turn):

```bash
python3 .agents/skills/infinite/scripts/infinite_state.py disarm --reason "user said stop"
```

Details, safety notes, and manual verification: [`references/openhands-enforcement.md`](skills/infinite/references/openhands-enforcement.md).

## Why it does not drift, stall, or fake progress

- **One target per round** — chosen by score from evidence, not vibes, so rounds
  have a reason and a result.
- **Escalation ladder** — as easy wins run out, rounds climb from *fix* to
  *prove* to *harden* to *simplify* to *extend*, instead of re-polishing the
  same line.
- **Durable ledger** — `.infinite/ledger.jsonl` survives context compaction,
  new sessions, and restarts; the loop resumes at the next round.
- **Anti-fake-progress rule** — a round that found nothing must say so and change
  axis; inventing a fix to look busy is forbidden.
- **Never leaves the workspace broken** — every round ends with checks passing,
  and checkpoints are committed.

## Limits, honestly

- OpenHands still ends a *run* at `max_iterations` (default `500`) and applies
  stuck detection. The ledger makes that boundary resumable rather than fatal:
  raise the limit, or send `continue` to resume mid-loop.
- Nothing can override a user who stops the process, closes the session, or
  revokes access. "Never stop" means **the agent never elects to stop**.
- Rounds cost tokens. The skill keeps each round small and evidence-driven, but
  an unbounded loop is meant to be watched, not left unattended for days.

## Safety

The loop is unconditional about continuing, not about consequences. The skill
forbids destructive or irreversible actions without a clear user request (no
force-pushes to shared branches, no data deletion, no spending money, no
publishing), forbids faking progress, and requires disarming on the first clear
stop. Do not arm the hook in a shared repository where other agents run without
the owner's knowledge.

## Repository layout

```
AI-Infinite-Skill/
├── skills/infinite/
│   ├── SKILL.md                     the loop contract and round procedure
│   ├── README.md                    skill-level docs
│   ├── commands/infinite.md         slash-command shim
│   ├── references/
│   │   ├── loop-protocol.md         ledger, checkpointing, resume, stop handling
│   │   ├── audit-playbook.md        domain checklists, scoring, escalation ladder
│   │   └── openhands-enforcement.md hook setup, arming, safety, limits
│   ├── scripts/
│   │   ├── infinite_state.py        ledger/report/arm/disarm (stdlib only)
│   │   ├── stop_hook.sh             OpenHands Stop hook entry point
│   │   └── install-openhands-hooks.sh  idempotent hook installer
│   └── assets/                      templates to copy into a project
├── tests/smoke.sh                   dependency-free smoke tests
└── README.md
```

## Development

```bash
bash tests/smoke.sh
```

Verifies the frontmatter, the state helper (init/log/status/report/disarm), the
Stop hook (armed denies with exit 2 and valid JSON, disarmed allows with exit 0,
discovery from subdirectories), and the installer (creates, is idempotent, and
preserves existing hooks).

## License

MIT — see [LICENSE](LICENSE).

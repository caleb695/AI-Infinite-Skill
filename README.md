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

### One command (recommended)

```bash
git clone https://github.com/caleb695/AI-Infinite-Skill
bash AI-Infinite-Skill/infinite/scripts/install-openhands-hooks.sh --dir . --install-skill
```

That places the skill at `.agents/skills/infinite/` (the location OpenHands
loads first), arms enforcement, and self-checks that a finish attempt is
actually denied. Use `--scope user` to install into `~/.agents/skills/` instead,
or `--no-arm` to install without enforcement.

No clone needed — the installer bootstraps itself (it fetches its own files from
the same commit):

```bash
curl -fsSL https://raw.githubusercontent.com/caleb695/AI-Infinite-Skill/main/infinite/scripts/install-openhands-hooks.sh \
  | bash -s -- --dir . --install-skill
```

Pin a tag or commit for reproducibility with `INFINITE_REF=<ref>`.

### Or copy it by hand

OpenHands scans, in priority order, `.agents/skills/`, `.openhands/skills/`, and
the legacy `.openhands/microagents/` — in the working directory and, if it is a
git repo, the repo root:

```bash
mkdir -p .agents/skills
cp -r infinite .agents/skills/infinite          # project scope
cp -r infinite ~/.agents/skills/infinite        # user scope, all projects
```

Claude Code and other Agent Skills clients read the same `SKILL.md` from
`.claude/skills/infinite`.

In Agent Canvas, enable it under **Customize > Skills** (`infinite`); headless
and CLI runs load `.agents/skills/` automatically. Trigger it by typing
`/infinite` in a message.

### Check the install

```bash
bash .agents/skills/infinite/scripts/install-openhands-hooks.sh --dir . --status
# project / mode / gates / rounds / finish attempts / last hook decisions
```

The installer also self-checks: it simulates a finish attempt and fails loudly if
it is not actually denied. Detected gates are probed first — a runner that is not
installed (e.g. no `pytest`) is skipped with a warning rather than armed as a gate
that could never pass.

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
# installs the guard, three hooks, and an immutable per-session policy
bash .agents/skills/infinite/scripts/install-openhands-hooks.sh --dir .
```

While `.infinite/ARMED` exists, every attempt to finish returns:

```json
{
  "decision": "deny",
  "reason": "Infinite mode is ARMED (round 7, next target: ...). Finishing is not allowed: the user has not said stop. Start round 8 now — ...",
  "additionalContext": "Infinite loop protocol: (1) re-read the latest user message ..."
}
```

The deny does not just block — OpenHands sends the `additionalContext` back to
the agent as a message and flips the run from `FINISHED` to `RUNNING`, so the
loop restarts with the failing gates, round number, and next target in context.

End it whenever you want:

```bash
bash .agents/skills/infinite/scripts/install-openhands-hooks.sh --dir . --disarm
```

Details, safety notes, and manual verification: [`infinite/references/openhands-enforcement.md`](infinite/references/openhands-enforcement.md).

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
├── infinite/                        the skill directory itself
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
bash tests/smoke.sh              # enforcement, bypass attempts, install paths
python3 tests/openhands_compat.py  # OpenHands loader + hook contract conformance
```

The smoke suite covers the frontmatter, the ledger helper, the stop gate
(failing gates, missing evidence, repeated attempts), nine agent bypass
attempts, tampering with on-disk state, and the user-only disarm paths. The
conformance suite re-implements OpenHands' actual loader and hook rules
(name/directory matching, `^[a-z0-9]+(-[a-z0-9]+)*$`, description limits,
snake_case event keys, exit-2 blocking, `additionalContext` delivery) and runs
the installed hooks the way the SDK does — from an unrelated cwd, with the SDK's
exact `HookEvent` JSON on stdin.

## License

MIT — see [LICENSE](LICENSE).

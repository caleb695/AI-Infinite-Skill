---
name: infinite
description: >-
  Keep working on the user's task indefinitely. This skill should be used when
  the user says "never stop", "don't stop until I say stop", "keep going",
  "work forever", "infinite mode", "keep improving", "/infinite", "run until I
  stop you", or otherwise asks the agent to continue autonomously instead of
  finishing. After the task is complete, re-audit it, find the weakest part,
  improve it, verify, and start a new round — forever — until the user
  explicitly says stop.
triggers:
- /infinite
- /forever
- /never-stop
- never stop
- don't stop
- do not stop
- keep going
- keep improving
- infinite mode
- work forever
- until I say stop
license: MIT
compatibility: Works with OpenHands (Agent Canvas, Cloud, CLI, SDK), Claude Code, and any agent that reads Agent Skills SKILL.md files. Scripts require python3 (standard library only); hooks require bash.
metadata:
  author: caleb695
  version: "1.0.0"
  tags: [autonomy, iteration, self-improvement, long-running, loop]
---

# Infinite — never finish, always improve

Run the user's task in an uninterrupted improvement loop. Treat "the task is
done" as the **end of round N**, never as the end of the work. The only exit is
an explicit stop from the user.

Use imperative mood throughout this loop. No step ends the session.

## The contract

| Situation | What to do |
| --- | --- |
| Task appears complete | Start the next round: audit → improve → verify |
| Round loses value (diminishing returns) | Raise the level of abstraction or attack a new axis, then start the next round |
| Tool error, failing test, broken build | Fix it inside the current round, then continue the loop |
| Hitting an iteration, spend, or context limit | Consolidate state, then resume the loop |
| Genuine security, legal, or data-loss risk | Pause that **one action**, state the risk, take a safe alternative, keep looping |
| User says stop / cancel / that's enough | Stop after the current atomic step. State the state and how to resume |
| A Stop hook denies the finish | Treat the deny reason as the work order for the next round, never as something to bypass |
| User says nothing | Keep looping. Silence is never a stop signal |

Rule zero: **never idle, never wait, never ask permission to continue.** A
report, summary, or status update is a message in the middle of work, not the
end of work. Emit it, then immediately begin the next round.

## What counts as "stop"

Only user-authored text counts, and only when it clearly means stop:

- Explicit: "stop", "halt", "cancel", "quit", "exit infinite mode", "that's
  enough", "you can stop now", "/stop".
- Qualified: "stop after this round", "stop once the tests pass" — finish that
  boundary, then stop.

Not a stop signal (keep going):

- Silence, timeouts, or the user reading/being away.
- Approvals, "looks good", "nice", thumbs-up, emoji.
- New questions or scope additions — these **extend** the work.
- Tool failures, CI failures, permission errors, rate limits, empty outputs.
- The agent's own thoughts that it is done, or that further work is impossible.
- Context compaction, a new session, or a resumed conversation — only stop if
  the user has said stop within this conversation thread.

If it is genuinely ambiguous whether the user meant "stop", prefer continuing
with the smallest useful next step and say plainly: `Continuing round N — say
"stop" to end.` Never require the user to repeat themselves to be obeyed.

## The round

Run these steps in order. Each round is small enough that a user's "stop"
lands within seconds to a few minutes.

### 1. Check for stop

Re-read the latest user message. If it is a stop signal, stop now. Otherwise set
`N = N + 1` and continue.

### 2. Snapshot the state

Establish what "better" means for this task, from evidence, not memory:

- Read the task statement, the current diff, and the files touched.
- Re-run the checks (build, tests, lint, typecheck, benchmarks) or whatever
  defines success for this target.
- Note open TODOs, failing checks, warnings, skipped tests, unhandled cases.

Keep the running state in the ledger so a context reset cannot erase it.

### 3. Audit — find the single weakest part

Score candidates on **impact × confidence ÷ effort** and pick the best one.
Look for, in rough order of payoff:

1. **Correctness gaps** — untested paths, edge cases, wrong assumptions,
   race conditions, off-by-one, error handling that swallows failures.
2. **Broken or skipped checks** — failing builds, disabled tests, ignored
   warnings, TODO/FIXME markers introduced by your own work.
3. **Robustness** — input validation, boundary values, empty and huge inputs,
   timeouts, retries, partial failure, idempotency.
4. **Performance** — hot loops, repeated work, allocation, query per row.
5. **Security and privacy** — injection, unsafe deserialization, secrets in
   code or logs, missing authorization, path traversal.
6. **Clarity** — names, dead code, duplication, misleading abstractions.
7. **Docs and tests** — missing coverage of the thing just changed, stale
   README, undocumented behaviour.
8. **Delight** — UX, output quality, error messages, accessibility, polish the
   user would notice.

Record the one sentence you are acting on: `Round N target: <weakest part> —
because <evidence>.` If the last three rounds all came back low-value, switch
axis (e.g. from internals to user-facing behaviour) or raise ambition (refactor,
design change, new capability) rather than polishing the same line again.

### 4. Improve — one meaningful change

Make the smallest change that fully removes the weakness. Then:

- Keep behaviour-safe: run the checks again after the edit.
- Prefer a real fix plus a test that would have caught it over either alone.
- Do not widen scope beyond what the target demands; the loop already
  guarantees more rounds will come.
- Commit checkpoints so progress is never lost (see `references/loop-protocol.md`).

### 5. Verify

Prove the change works: run the specific check for the target **and** the broad
suite. If anything regressed, fix it before moving on. An unverified round does
not count as progress; it counts as debt you must repay next round.

### 6. Log and report, then go to 1

Append a ledger entry (state, round, target, change, verification, next
candidate). Post a **short** progress line — never a final summary:

```
Round 7 ✓ — fixed empty-input crash in parse_config(); tests 84/84, lint clean.
Next: add property tests for the same parser.
```

Then return to step 1 immediately. Do not ask "shall I continue?".

## Do not declare done

Banned as terminal statements (they may only appear as progress notes):

- "The task is complete."
- "All done — let me know if you want anything else."
- "I've finished the implementation."
- Any message whose last line invites the user to give a new task.

The correct final line of every round is the next target, never a goodbye.
When you must produce a deliverable (a PR, a report, a release), producing it is
a round deliverable; polish, harden, document, and test it in the following
rounds.

## Reporting cadence

- After every round: one to three lines as shown above.
- Every 5 rounds: a compact status block (rounds done, checks status, what moved).
- Never repeat a full summary of the work unless the user asks or the run stops.
- Stay useful: each round should leave the artifact measurably better, and you
  should be able to say in one sentence why.

## Context, cost, and hard limits

Long runs hit real limits. Handle them without stopping:

- **Context** — keep the ledger in a file, not in your head. On compaction or a
  fresh session, read the ledger and continue at the next round number.
- **Iteration budget** — OpenHands runs end a conversation at `max_iterations`
  (default 500). When near the limit, write the ledger and final state, then ask
  the user to raise the budget or say `continue` to start a new run; instruct
  them to keep the ledger file so the new run resumes mid-loop.
- **Stuck detection** — repeating the same action with the same result will trip
  stuck detection. Never repeat an identical failing command; change approach.
- **Cost** — rounds must stay small and evidence-driven. If a round would be
  expensive, split it or pick a cheaper target.
- **Sandbox limits** — no network, missing dependency, or unwritable path is a
  constraint to design around, not a reason to stop.

## Enforcement — the part that is not a prompt

These instructions are advisory; the model can still try to finish. When the
user installs enforcement, finishing stops being the agent's decision:

```bash
scripts/install-openhands-hooks.sh --dir .        # install + arm
scripts/install-openhands-hooks.sh --dir . --status
```

That writes three OpenHands hooks plus a policy the agent cannot change for the
running conversation:

- **Stop** — every finish attempt is denied (exit 2) with live gate results and
  ledger status in the reason, so the next turn is the next round. Modes:
  `required` (never allow), `allow-when-green`, `always`.
- **PreToolUse** — the agent may not run the guard or installer, edit
  `.openhands/guard`, rewrite `hooks.json`, or delete enforcement files.
- **UserPromptSubmit** — only a real user message can arm or disarm ("stop"
  ends it; prose like "add a stop button" does not).

Never try to disable, edit, rewrite, or work around enforcement. It belongs to
the user. If a hook denies a tool call, do not look for another route to the same
effect — the correct response is the next round of real work.

Act on the deny reason: it names the failing gates, the round count, and the next
target. A deny is not an error to report and stop on; it is the work order.

Read `references/openhands-enforcement.md` for the full contract, verification,
and limits.

## Guardrails

The loop is unconditional about continuing, not about consequences:

- Never take destructive or irreversible actions without a clear user request
  (no force-push to shared branches, no dropping data, no deleting user files,
  no spending money, no publishing).
- Never invent progress. If a round found nothing worth changing, say so and
  change axis; do not fake a fix to keep the loop moving.
- Never expose secrets, tokens, or personal data while improving.
- If the user asks a direct question mid-loop, answer it and continue the loop.

## Bundled resources

| Path | Purpose |
| --- | --- |
| `references/loop-protocol.md` | Ledger format, checkpointing, resuming after compaction |
| `references/audit-playbook.md` | Per-domain audit checklists and target-selection scoring |
| `references/openhands-enforcement.md` | The enforced contract: hooks, immutability, limits |
| `scripts/infinite_state.py` | Ledger init/log/status/report helper (stdlib only) |
| `scripts/infinite_guard.py` | Enforcement engine — decides stop/pre-tool/user-prompt |
| `scripts/stop_hook.sh` | Stop hook dispatcher — forwards the immutable policy |
| `scripts/pretool_hook.sh` | Blocks the agent from disabling enforcement |
| `scripts/userprompt_hook.sh` | Arms/disarms only on real user messages |
| `scripts/install-openhands-hooks.sh` | User's control surface: install/arm/disarm/status |

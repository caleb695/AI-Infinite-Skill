# Loop protocol — durable state for endless runs

An endless loop only works if it survives the things that kill long runs:
context compaction, a new conversation, a crashed tool, an iteration cap. Keep
the loop in files, not in memory.

## Where state lives

```
<project>/.infinite/
├── state.json     current round, phase, next target
└── ledger.jsonl   append-only round history (never rewritten)

<project>/.openhands/guard/     enforcement state (user-owned, see openhands-enforcement.md)
├── config.json    mirror of the armed policy
├── attempts.json  finish attempts, for the "tried again without a round" message
├── DISARMED       present after the user says stop
└── events.jsonl   audit trail of arm/disarm/deny decisions
```

`.infinite/` is scratch state. Add it to `.gitignore` unless the user wants the
ledger committed as a deliverable. Never commit `.openhands/guard/`.

Use `scripts/infinite_state.py` for all reads and writes:

```bash
python3 scripts/infinite_state.py init --task "make the CLI robust"
python3 scripts/infinite_state.py status
python3 scripts/infinite_state.py next-target "handle broken pipe on stdout"
python3 scripts/infinite_state.py log \
  --target "broken pipe crash" \
  --change "catch BrokenPipeError in main()" \
  --verification "tests 96/96, manual: yes | head -1 runs clean" \
  --next "property tests for argument parsing"
python3 scripts/infinite_state.py report
```

Arming and disarming are the user's actions, not yours: they happen through the
installer and the conversation (`stop`), never through the agent. See
[`openhands-enforcement.md`](openhands-enforcement.md).

If the scripts are unavailable, keep the same information by hand in
`.infinite/ledger.jsonl` and `.infinite/state.json`. The format matters less
than the fact that the next round can be reconstructed from disk.

## Round record

One JSON object per line, appended after each completed round:

```json
{"ts":"2026-11-04T18:22:03+00:00","event":"round","round":7,"target":"empty input crash","change":"guard len==0 in parse_config","verification":"tests 84/84, lint clean","next":"property tests for parse_config","notes":"found via fuzz seed 12"}
```

Rules:

- Append only. Never rewrite history to look better than it was.
- `verification` must be something you actually ran, quoted with its result.
- `next` is mandatory in practice: it is how the loop restarts after a context
  reset.

## Checkpointing

- After each round, leave the workspace in a state that builds and tests clean.
  An endless loop must never end a round in a broken state.
- Commit at meaningful boundaries (`git add -A && git commit -m "round N: <target>"`)
  when the project is a git repo and the user has not asked you not to.
- Never force-push, never rewrite shared history, never commit secrets.
- Keep an untracked scratch file for half-finished experiments; delete it or
  finish it within the same round.

## Resuming

On a new conversation, after compaction, or when told to `continue`:

1. `python3 scripts/infinite_state.py status` — read round, phase, armed.
2. `python3 scripts/infinite_state.py report --limit 10` — read recent rounds.
3. Re-run the project's checks to learn the real current state (the ledger may
   predate a change made outside the loop).
4. Continue at `round + 1` with the recorded next target, or re-audit if the
   recorded target no longer applies.
5. Do not restart numbering at 1, and do not re-announce the task.

If no state exists at all but the user's instruction still holds (they asked
for an infinite loop and have not stopped), reconstruct the ledger from the
conversation and continue.

## When the user says stop

1. Finish the atomic step in progress; do not leave a half-applied edit.
2. Run the checks one last time and fix anything you broke.
3. Stop: the user's message or `--disarm` releases the Stop hook. Do not try to
   disarm it yourself — the PreToolUse hook blocks that, by design.
4. Give a single closing summary: rounds completed, what changed, verification
   status, remaining known weaknesses. This is the one moment a final summary
   is correct.
5. On a later `continue` or `/infinite`, resume at the next round.

## Anti-patterns

- Storing the plan only in the conversation. Compaction will eat it.
- Repeating the same failing command. This trips stuck detection and wastes the
  round; change the approach instead.
- Logging rounds you did not verify. It makes the ledger worthless.
- Letting the ledger grow descriptions instead of evidence. One line, with the
  command and its result.

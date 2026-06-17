# Pattern: Bounded Iteration with Cross-Context State

## Problem
An agent — whether a shell script, LLM tool loop, crawler, or cron job —
cannot iterate unboundedly within a single execution context.
Resources, timeouts, and context windows are all finite.

## Solution

```
MAX_ITERATIONS per context-unit (run / session / turn)
  → on limit: write checkpoint to state-file
  → next context-unit: read state-file, resume from cursor
  → normal completion: delete state-file
```

## Shell implementation (from qnap/fix-symlink-loops.sh)

```sh
MAX_ITERATIONS=200
STATE_FILE="/tmp/agent.state"
iteration=0

for item in $work_queue; do
  iteration=$((iteration + 1))
  if [ "$iteration" -ge "$MAX_ITERATIONS" ]; then
    printf '%s\n' "$item" > "$STATE_FILE"   # checkpoint
    exit 0                                   # clean exit; next run resumes
  fi
  process "$item"
done
rm -f "$STATE_FILE"   # finished cleanly
```

## Mapping: Script ↔ LLM Agent

| Script concept       | LLM agent concept                          |
|----------------------|--------------------------------------------|
| `MAX_ITERATIONS`     | `max_steps` / `max_loop` in agent framework|
| State file           | `.ai/memory/` or agent scratchpad          |
| Next cron run        | Next LLM turn / tool-call cycle            |
| Idempotent marker    | Already-seen set / deduplication memory    |
| `exit 0` on limit    | Return control to orchestrator             |
| Clean finish         | Mark task complete in memory               |

## Why this matters for .ai folder design

Every file in `.ai/` is a checkpoint artefact — it exists so the
next agent context (human or LLM) can resume without loss of intent.
`index.md` is the cursor. `sessions/` are the state files.
This is not metaphorical: the `.ai/` folder *is* the state file
for the development agent.

## Variants
- **Token budget variant**: replace iteration counter with estimated token cost
- **Time budget variant**: `deadline=$(date -d '+5 minutes' +%s)` check in loop
- **Depth limit variant**: pass `depth` counter through recursion, abort at max

## References
- `qnap/fix-symlink-loops.sh` — origin of this pattern
- `.ai/patterns/scope-safeguards.md` — what to iterate over
- `.ai/patterns/marker-as-memory.md` — what to write on each iteration

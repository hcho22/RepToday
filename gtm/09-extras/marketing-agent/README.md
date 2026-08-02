# Rep Today creative loop (dry run)

This is the runnable dry-run half of `BUILD-SPEC.md`.
It has never been run against a real ad account.
It publishes nothing, reads no credentials, and touches no network: Python 3 standard library only.

## Run it in 3 commands

```sh
python3 creative_loop.py generate    # angle bank -> creative briefs + JSON log in out/
python3 creative_loop.py qa          # brand-rules lint of every brief (exit 1 on any fail)
python3 creative_loop.py scoreboard  # angle table with honest null results
```

A fourth command, `python3 creative_loop.py publish`, exists only to prove the rail: it raises `NotImplementedError` naming the founder decision required, and exits nonzero.

## Files

- `creative_loop.py` - the CLI (generate, qa, scoreboard, and the disabled publish stub).
- `angles.seed.json` - 7 seed angles, each tracing to a real mined pain in `../../01-research/pain-point-frequency.md` with its real source URL.
- `brand-rules.json` - the machine-checkable lint rules extracted from `../../02-brand/brand-guidelines.md`.
- `out/` - generated evidence from a verified local dry run: one brief per angle plus `creative-log.json` with every result field null.

## Honesty note

The scoreboard's result columns are null because nothing has been published, and no code path here can fill them with anything but real data.
Do not add fake numbers to demo it; the null table is the correct demo.

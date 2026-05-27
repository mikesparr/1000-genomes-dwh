# 1000 Genomes Data Warehouse — Reproducibility Runbook

This runbook captures every command, configuration, and resolution from building the
warehouse from scratch on a fresh machine. Each per-phase file pairs the commands
with their actual terminal output, so anyone replaying these steps can verify they
got the same result.

## How to use this runbook

- Follow the phases in order. Each builds on the previous one.
- Don't skip the verification commands — they're how you'll know each phase succeeded.
- When a step's output doesn't match what's documented here, stop and diagnose.
  Catching divergence early is much cheaper than catching it three phases later.

## Phases

- [Phase 0 - Python, dbt, pre-commit, sqlfluff setup](phase-0-environment.md)
- [Phase 1 - 1KG samples + chr22 extraction + ref data](phase-1-data-fetch.md)
- [Phase 2 - VCF → Parquet, panel, GENCODE, ClinVar](phase-2-bronze.md)
- [Phase 3 - patients, panels, trajectories](phase-3-synth.md)
- [Phase 4 - 9 staging views + source declarations](phase-4-staging.md)
- [Phase 5 - 3 int tables + custom tests](phase-5-intermediate.md)
- [Phase 6 - dimensions, facts, OBT marts, snapshot](phase-6-marts.md)
- [Phase 7 - port + benchmark capture](phase-7-snowflake.md)
- [Phase 8 - README, docs, analyses](phase-8-docs.md)
- [Phase 9 - Dagster orchestration](phase-9-dagster.md)

## Environment assumptions

- macOS Sonoma+ or recent Linux
- Python 3.12+ in a venv
- Homebrew for system tools (DuckDB, bcftools, AWS CLI)
- ~200GB free disk space if running the full 50-sample fetch

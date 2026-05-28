# Raw Data Loading
The loader scripts and initial database schemas.

## Ingestion Sequence (with Failure Handling)

```mermaid
%%{init: {'theme':'dark'}}%%
sequenceDiagram
    participant SRC as AWS S3<br/>(1000 Genomes)
    participant LOAD as Python Loader
    participant DLQ as Dead-Letter<br/>local path
    participant DDB as DuckDB<br/>(local file)
    participant BR as bronze.raw_1kg__variants
    participant AUD as ops.load_audit

    LOAD->>AUD: INSERT (load_id, started_at, source_uri)
    LOAD->>SRC: stream VCF, parse with cyvcf2
    LOAD->>LOAD: convert to Parquet,<br/>add load_id, ingested_at
    alt parse error
        LOAD->>DLQ: write bad record + reason
        LOAD->>AUD: increment error_count
    else ok
        LOAD->>DDB: COPY into Bronze<br/>(or read_parquet directly)
    end
    DDB-->>BR: rows materialized
    LOAD->>AUD: UPDATE finished_at, status, counts
    Note over BR,AUD: bronze rows tagged with load_id<br/>→ trivially re-runnable & rollback-able
```

**Resiliency principles baked in:**

- **Append-only Bronze** with `load_id` and `ingested_at` audit columns. Never `DELETE` — re-runs become a `WHERE load_id NOT IN (failed_loads)` filter in Silver.
- **Idempotent Bronze loads** — if you re-run for the same `source_uri`, you get the same `load_id` (deterministic hash) and old rows are dropped before insert via `MERGE`, or you stamp them inactive.
- **Dead-letter prefix** for malformed VCF rows so analysts can audit data quality.
- **Snapshot the DuckDB file** before risky transformations (`cp warehouse.duckdb warehouse.duckdb.bak`) — poor-man's time travel. When you port to Snowflake, real Time Travel takes over (default 1 day, up to 90 on Enterprise).
- **Incremental Bronze→Silver** via dbt's `is_incremental()` pattern, gated on `load_id`.
Welcome to our dbt project!

## Medallion Layer Mapping
```mermaid
%%{init: {'theme':'dark'}}%%
flowchart TB
    subgraph BRONZE["🥉 BRONZE — raw, immutable, append-only"]
        BR1["raw_1kg__variants<br/>(VCF rows, exact)"]
        BR2["raw_1kg__samples"]
        BR3["raw_synth__patients"]
        BR4["raw_synth__mrd_tests"]
        BR5["raw_ref__genes"]
        BR6["raw_ref__clinvar"]
    end

    subgraph SILVER["🥈 SILVER — typed, deduped, conformed"]
        S1["stg_1kg__variants<br/>(view, 1:1, renamed)"]
        S2["stg_1kg__samples"]
        S3["stg_synth__patients"]
        S4["stg_synth__mrd_tests"]
        S5["stg_ref__genes"]
        S6["stg_ref__clinvar"]
        I1["int_variants__annotated<br/>(variants + gene + clinvar)"]
        I2["int_patients__panel_designed<br/>(picks 16 variants per patient)"]
        I3["int_mrd__test_with_panel<br/>(joins tests to panel & patient)"]
    end

    subgraph GOLD["🥇 GOLD — business-ready star schema"]
        G1["dim_patient"]
        G2["dim_variant"]
        G3["dim_gene"]
        G4["dim_population"]
        G5["dim_date"]
        G6["dim_panel"]
        G7["fct_variant_observation<br/>(sample × variant)"]
        G8["fct_mrd_test"]
        G9["fct_clinical_event"]
        G10["mart_pharma__cohort_extract<br/>(governed wide table)"]
        G11["mart_clin__patient_timeline"]
    end

    BR1 --> S1
    BR2 --> S2
    BR3 --> S3
    BR4 --> S4
    BR5 --> S5
    BR6 --> S6
    S1 --> I1
    S5 --> I1
    S6 --> I1
    S2 --> I2
    I1 --> I2
    S3 --> I2
    S4 --> I3
    I2 --> I3

    I1 --> G2
    I1 --> G3
    I2 --> G1
    I2 --> G6
    S2 --> G4
    I1 --> G7
    I3 --> G8
    S3 --> G9

    G1 --> G10
    G6 --> G10
    G8 --> G10
    G9 --> G10
    G1 --> G11
    G8 --> G11
    G9 --> G11

    classDef bronze fill:#8b4513,stroke:#ffa500,color:#fff,stroke-width:2px
    classDef silver fill:#475569,stroke:#cbd5e1,color:#fff,stroke-width:2px
    classDef gold fill:#b8860b,stroke:#fde047,color:#fff,stroke-width:2px
    class BR1,BR2,BR3,BR4,BR5,BR6 bronze
    class S1,S2,S3,S4,S5,S6,I1,I2,I3 silver
    class G1,G2,G3,G4,G5,G6,G7,G8,G9,G10,G11 gold
```

**Why this layering matters** (lifted from current dbt guidance): Bronze — raw data, loaded as-is from source systems · Silver — cleaned, deduplicated, and properly typed data · Gold — aggregated, business-ready tables for reporting and analytics. Bronze Layer = Staging Models (stg_) - One-to-one source relationships · Silver Layer = Intermediate Models (int_) - Business logic transformations · Gold Layer = Marts (dim_, fct_) - Business-ready data products.

The Bronze/Silver/Gold language and the dbt staging/intermediate/marts language describe the same pattern; this project uses both consistently — **Bronze = `raw_*` tables, Silver = `stg_*` (views) + `int_*` (tables), Gold = `dim_* / fct_* / mart_*`**.

---

## The Linking Strategy

The Linking Strategy

```mermaid
%%{init: {'theme':'dark'}}%%
flowchart LR
    subgraph REAL["Real (immutable)"]
        R1["1KG sample_id<br/>e.g. HG00096"]
        R2["1KG VCF rows<br/>chrom-pos-ref-alt"]
    end

    subgraph BRIDGE["Bridge layer"]
        B1["patient_id<br/>(synthetic UUID)"]
        B2["sample_id ↔ patient_id<br/>seed table"]
    end

    subgraph SYNTH["Synthetic"]
        S1["patient clinical attrs"]
        S2["panel definition<br/>(patient_id, variant_key)"]
        S3["mrd_test events<br/>(patient_id, test_date)"]
        S4["per-variant detection<br/>(test_id, variant_key, vaf)"]
    end

    R1 --- B2
    B2 --- B1
    B1 --> S1
    B1 --> S2
    B1 --> S3
    R2 -. "variant_key:<br/>chrom_pos_ref_alt" .-> S2
    S2 --> S4
    S3 --> S4
```

The **`variant_key = chrom || '_' || pos || '_' || ref || '_' || alt`** is the natural key shared across genomic and clinical worlds. This is the join you'll write a hundred times — make it a macro on day one.

---

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

---

## dbt Materialization Strategy (DuckDB & Snowflake)

| Layer | Materialization | Why |
|---|---|---|
| `raw_*` | Bronze table, loaded by Python, *not* a dbt model | dbt doesn't own ingestion — it's downstream |
| `stg_*` | **view** | Cheap, always fresh, no storage; it's just a typed alias of bronze |
| `int_*` | **table** (or **ephemeral** for tiny utility transforms) | Materialize once per run so downstream marts join from real tables |
| `dim_*` | **table** (full refresh nightly is fine for dims < 10M rows) | Small, queried often, full rebuild simpler than incremental edge cases |
| `fct_variant_observation` | **incremental** with `unique_key=['sample_id_1kg','variant_key']`, `on_schema_change='append_new_columns'` | This is the billion-row table; full rebuilds are expensive |
| `fct_mrd_test` | **incremental** with `unique_key='test_sk'` | Time-series; only new test dates each run |
| `mart_*` | **table** (or materialized view in Snowflake) for hot ones | Optimized for end-user query speed |

This mapping follows the canonical dbt guidance: staging: +materialized: view, intermediate: +materialized: table, marts: +materialized: table.

**The same materializations work in both DuckDB and Snowflake.** The differences show up only in the *physical optimization* layer — clustering keys, search optimization, automatic clustering services — which we'll wrap in Jinja conditionals (`{% if target.name == 'snowflake' %}`) so the project runs end-to-end in either target.

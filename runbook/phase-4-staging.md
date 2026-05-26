# Phase 4 - Staging layer
**Goal:** declare every Bronze Parquet file as a dbt source (using dbt-duckdb's external_location pattern), then write stg_* views that rename and type-cast columns. Staging models are intentionally thin — pure renames, no joins, no business logic.

## Commands (step-by-step)
```bash
#######################################################
# 4. STAGING LAYER
# - declare every Bronze Parquet file as a dbt source (dbt-duckdb's external_location)
#   then write `stg_*` views that rename and type-cast columns. Intentionally thin,
#   not using `COPY INTO` step given Parquet files on disk are the Bronze layer.
#######################################################

# declare $DWH_REPO_ROOT using direnv (optional, otherwise just export var)
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc   # or ~/.bashrc
source ~/.zshrc
cd ~/Documents/code/1000-genomes-dwh
echo 'export DWH_REPO_ROOT=$(pwd)' > .envrc   # warning ok, continue
direnv allow

# set up dbt staging directory structure
cd ~/Documents/code/1000-genomes-dwh/genomics_dwh
mkdir -p models/staging/{1kg,synth,ref}

# confirm var
ls "$DWH_REPO_ROOT/bronze/" | head

# add utils dependency
cat > packages.yml <<'EOF'
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
EOF

# create models/staging/_sources.yml
cat > models/staging/_sources.yml <<'EOF'
version: 2

sources:
  - name: bronze
    description: "Lakehouse Bronze layer — Parquet files produced by Phase 2 and 3 loaders."
    config:
      meta:
        external_location: "read_parquet('{{ env_var('DWH_REPO_ROOT', '..') }}/bronze/{name}.parquet')"
    tables:
      - name: raw_1kg__samples
        description: "1000 Genomes sample panel (population, sex, family)"
        columns:
          - name: sample
            tests: [not_null, unique]

      - name: raw_synth__patients
        description: "Synthetic patient demographics"
        columns:
          - name: patient_id
            tests: [not_null, unique]
          - name: sample_id_1kg
            tests: [not_null]
          - name: stage_at_diagnosis
            tests:
              - accepted_values:
                  arguments:
                    values: ['I', 'II', 'III', 'IV']

      - name: raw_synth__panels
        description: "Synthetic personalized panels (16 variants per patient)"
        columns:
          - name: patient_id
            tests: [not_null]
          - name: variant_key
            tests: [not_null]

      - name: raw_synth__mrd_tests
        description: "Synthetic serial MRD test events"
        columns:
          - name: test_id
            tests: [not_null, unique]

      - name: raw_synth__mrd_detections
        description: "Synthetic per-variant detection signals at each MRD test"
        columns:
          - name: detection_id
            tests: [not_null, unique]

      - name: raw_synth__clinical_events
        description: "Synthetic clinical events (diagnosis, surgery, chemo, recurrence)"
        columns:
          - name: event_id
            tests: [not_null, unique]

      - name: raw_ref__genes
        description: "GENCODE gene annotation, chr22 only"

      - name: raw_ref__clinvar
        description: "ClinVar variant clinical significance, chr22 only"

  # The variant Parquet is hive-partitioned, so it needs a different read pattern.
  - name: bronze_variants
    description: "Per-sample chr22 variant Parquet (hive-partitioned)."
    config:
      meta:
        external_location: "read_parquet('{{ env_var('DWH_REPO_ROOT', '..') }}/bronze/raw_1kg__variants/**/*.parquet', hive_partitioning=true)"
    tables:
      - name: raw_1kg__variants
        description: "Per-sample chr22 variants from 1KG DRAGEN reanalysis"
        columns:
          - name: chromosome
            tests: [not_null]
          - name: position
            tests: [not_null]
          - name: sample_id
            tests: [not_null]
EOF

# create models/staging/1kg/stg_1kg__variants.sql - 1kg staging models
cat > models/staging/1kg/stg_1kg__variants.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze_variants', 'raw_1kg__variants') }}
),

renamed as (
    select
        sample_id,
        chromosome,
        cast(position as bigint)            as position,
        ref_allele,
        alt_allele,
        chromosome || '_' || position || '_' || ref_allele || '_' || alt_allele
                                            as variant_key,
        variant_type,
        genotype,
        cast(read_depth as integer)         as read_depth,
        cast(variant_allele_count as integer) as variant_allele_count,
        cast(variant_allele_freq as double) as variant_allele_freq,
        cast(quality as double)             as quality,
        filter_status,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/1kg/stg_1kg__samples.sql
cat > models/staging/1kg/stg_1kg__samples.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_1kg__samples') }}
),

renamed as (
    select
        sample              as sample_id,
        pop                 as population_code,
        super_pop           as super_population,
        lower(gender)       as sex_at_birth,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/1kg/_1kg__models.yml
cat > models/staging/1kg/_1kg__models.yml <<'EOF'
version: 2

models:
  - name: stg_1kg__variants
    description: "Typed, renamed view over per-sample chr22 variants from 1KG DRAGEN."
    columns:
      - name: variant_key
        description: "Canonical chrom_pos_ref_alt key for cross-source joining."
        tests: [not_null]
      - name: sample_id
        tests: [not_null]
      - name: chromosome
        tests:
          - accepted_values:
              arguments:
                values: ['chr22']  # in this slice; broaden when scaling up
      - name: variant_type
        tests:
          - accepted_values:
              arguments:
                values: ['SNV', 'INSERTION', 'DELETION', 'MNP', 'OTHER']

  - name: stg_1kg__samples
    description: "1000 Genomes sample metadata (population, sex)."
    columns:
      - name: sample_id
        tests: [not_null, unique]
      - name: super_population
        tests:
          - accepted_values:
              arguments:
                values: ['AFR', 'AMR', 'EAS', 'EUR', 'SAS']
      - name: sex_at_birth
        tests:
          - accepted_values:
              arguments:
                values: ['male', 'female']
EOF

# write the models/staging/synth/stg_synth__patients.sql
cat > models/staging/synth/stg_synth__patients.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_synth__patients') }}
),

renamed as (
    select
        patient_id,
        sample_id_1kg,
        tumor_type,
        stage_at_diagnosis,
        cast(age_at_diagnosis as integer)        as age_at_diagnosis,
        sex_at_birth,
        ancestry_super_pop                       as ancestry_super_population,
        ancestry_pop                             as ancestry_population_code,
        cast(diagnosis_date as date)             as diagnosis_date,
        cast(primary_surgery_date as date)       as primary_surgery_date,
        trial_id,
        treatment_arm,
        cast(consented_for_research as boolean)  as consented_for_research,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/synth/stg_synth__panels.sql
cat > models/staging/synth/stg_synth__panels.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_synth__panels') }}
),

renamed as (
    select
        panel_id,
        patient_id,
        cast(variant_index as integer)         as variant_index,
        chromosome,
        cast(position as bigint)               as position,
        ref_allele,
        alt_allele,
        variant_key,
        cast(simulated_tumor_vaf as double)    as simulated_tumor_vaf,
        cast(panel_design_date as date)        as panel_design_date,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/synth/stg_synth__mrd_tests.sql
cat > models/staging/synth/stg_synth__mrd_tests.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_synth__mrd_tests') }}
),

renamed as (
    select
        test_id,
        patient_id,
        panel_id,
        cast(test_date as date)                 as test_date,
        cast(test_sequence_number as integer)   as test_sequence_number,
        cast(days_since_surgery as integer)     as days_since_surgery,
        cast(is_positive as boolean)            as is_positive,
        cast(mtm_per_ml as double)              as mtm_per_ml,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/synth/stg_synth__mrd_detections.sql
cat > models/staging/synth/stg_synth__mrd_detections.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_synth__mrd_detections') }}
),

renamed as (
    select
        detection_id,
        test_id,
        patient_id,
        variant_key,
        cast(vaf_blood as double)    as vaf_blood,
        cast(is_detected as boolean) as is_detected,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/synth/stg_synth__clinical_events.sql
cat > models/staging/synth/stg_synth__clinical_events.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_synth__clinical_events') }}
),

renamed as (
    select
        event_id,
        patient_id,
        cast(event_date as date) as event_date,
        event_type,
        event_subtype,
        regimen,
        outcome,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/synth/_synth__models.yml
cat > models/staging/synth/_synth__models.yml <<'EOF'
version: 2

models:
  - name: stg_synth__patients
    description: "Synthetic patient demographics anchored on real 1KG samples."
    columns:
      - name: patient_id
        tests: [not_null, unique]
      - name: sample_id_1kg
        tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_1kg__samples')
                field: sample_id
      - name: stage_at_diagnosis
        tests:
          - accepted_values:
              arguments:
                values: ['I', 'II', 'III', 'IV']
      - name: sex_at_birth
        tests:
          - accepted_values:
              arguments:
                values: ['male', 'female']
      - name: ancestry_super_population
        tests:
          - accepted_values:
              arguments:
                values: ['AFR', 'AMR', 'EAS', 'EUR', 'SAS']

  - name: stg_synth__panels
    description: "Personalized panels: ~16 variants per patient."
    columns:
      - name: panel_id
        tests: [not_null]
      - name: patient_id
        tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_synth__patients')
                field: patient_id
      - name: variant_key
        tests: [not_null]
      - name: simulated_tumor_vaf
        tests:
          - dbt_utils.accepted_range:
              arguments:
                min_value: 0
                max_value: 1

  - name: stg_synth__mrd_tests
    description: "Serial MRD test events per patient."
    columns:
      - name: test_id
        tests: [not_null, unique]
      - name: patient_id
        tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_synth__patients')
                field: patient_id
      - name: panel_id
        tests: [not_null]
      - name: is_positive
        tests: [not_null]
      - name: days_since_surgery
        tests:
          - dbt_utils.accepted_range:
              arguments:
                min_value: 0

  - name: stg_synth__mrd_detections
    description: "Per-panel-variant detection signal at each MRD test."
    columns:
      - name: detection_id
        tests: [not_null, unique]
      - name: test_id
        tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_synth__mrd_tests')
                field: test_id
      - name: patient_id
        tests: [not_null]
      - name: variant_key
        tests: [not_null]
      - name: vaf_blood
        tests:
          - dbt_utils.accepted_range:
              arguments:
                min_value: 0
                max_value: 1

  - name: stg_synth__clinical_events
    description: "Clinical events: diagnosis, surgery, chemo, recurrence."
    columns:
      - name: event_id
        tests: [not_null, unique]
      - name: patient_id
        tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_synth__patients')
                field: patient_id
      - name: event_type
        tests:
          - accepted_values:
              arguments:
                values: ['diagnosis', 'surgery', 'chemotherapy_start', 'recurrence', 'imaging', 'death']
EOF

# write models/staging/ref/stg_ref__genes.sql
cat > models/staging/ref/stg_ref__genes.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_ref__genes') }}
),

renamed as (
    select
        ensembl_id,
        gene_symbol,
        chromosome,
        cast(start_position as bigint) as gene_start,
        cast(end_position as bigint)   as gene_end,
        strand,
        biotype,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# write models/staging/ref/stg_ref__clinvar.sql
cat > models/staging/ref/stg_ref__clinvar.sql <<'EOF'
{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_ref__clinvar') }}
),

renamed as (
    select
        chromosome,
        cast(position as bigint) as position,
        ref_allele,
        alt_allele,
        chromosome || '_' || position || '_' || ref_allele || '_' || alt_allele as variant_key,
        rsid,
        clnsig     as clinvar_significance,
        clndn      as clinvar_disease_names,
        clnrevstat as clinvar_review_status,
        geneinfo,
        load_id,
        ingested_at
    from source
)

select * from renamed
EOF

# create models/staging/ref/_ref__models.yml
cat > models/staging/ref/_ref__models.yml <<'EOF'
version: 2

models:
  - name: stg_ref__genes
    description: "GENCODE v44 gene annotation, chr22 only."
    columns:
      - name: ensembl_id
        tests: [not_null, unique]
      - name: gene_symbol
        tests: [not_null]
      - name: chromosome
        tests:
          - accepted_values:
              arguments:
                values: ['chr22']  # in this slice; broaden when scaling up
      - name: biotype
        tests: [not_null]
      - name: strand
        tests:
          - accepted_values:
              arguments:
                values: ['+', '-']

  - name: stg_ref__clinvar
    description: "ClinVar variant clinical significance, chr22 only, normalized to chr-prefixed naming."
    columns:
      - name: variant_key
        tests: [not_null]
      - name: chromosome
        tests:
          - accepted_values:
              arguments:
                values: ['chr22']
EOF

# ensure you are running the .venv dbt-core and not global fusion from VSCode extension
which dbt
source ../.venv/bin/activate
pip install --upgrade dbt-duckdb
which dbt
# Expect: /PATH/TO/YOUR/code/1000-genomes-dwh/.venv/bin/dbt

# Compile-only check (catches syntax errors before running)
dbt compile --select staging
# ... Found 9 models, 64 data tests, 9 sources, 601 macros

# Build all staging views
dbt build --select staging
# 05:18:09  Finished running 64 data tests, 9 view models in 0 hours 0 minutes and 0.59 seconds (0.59s).
# 05:18:09  
# 05:18:09  Completed successfully
# 05:18:09  
# 05:18:09  Done. PASS=73 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=73

# Sanity-check one of the views
duckdb ../warehouse.duckdb -c "
  SELECT chromosome, count(DISTINCT sample_id) AS samples, count(*) AS variants
  FROM main.stg_1kg__variants
  GROUP BY 1
"

# ┌────────────┬─────────┬──────────┐
# │ chromosome │ samples │ variants │
# │  varchar   │  int64  │  int64   │
# ├────────────┼─────────┼──────────┤
# │ chr22      │      50 │  4744579 │
# └────────────┴─────────┴──────────┘

# commit progress on staging
cd ..
sqlfluff lint
# if errors: sqlfluff fix
git add genomics_dwh/models/staging/ .gitignore .python-version genomics_dwh/package*.yml
git commit -m "Phase 4: staging layer — dbt sources + stg_* views over Bronze Parquet"
# sqlfluff-lint............................................................Passed
# [main fea457f] Phase 4: staging layer — dbt sources + stg_* views over Bronze Parquet
```
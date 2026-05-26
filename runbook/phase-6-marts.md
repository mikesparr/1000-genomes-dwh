# Phase 6 - Gold Marts layer
**Goal:** build the star-schema dimensions and facts plus the two OBT marts. This is where Staff-DE-level thinking earns its keep — surrogate keys, SCD-2, sort/cluster choices, and the deliberate denormalization of OBT marts alongside the normalized star.

## Commands (step-by-step)
```bash
#######################################################
# 6. GOLD MART LAYER
# - build the star-schema dimensions and facts plus two OBT marts. 
#   Notable: surrogate keys, SCD-2, sort/cluster choices, and
#   deliberate denormalization of OBT marts alongside normalized star.
#
# - reusable macros
# - join tables (variants, panels, MRD tests)
# - custom tests
#######################################################

# change to dbt project dir and set up marts directory
cd genomics_dwh
mkdir -p models/marts/{core,clinical,pharma}
mkdir -p snapshots

# update the dbt_project.yml file
cat > dbt_project.yml <<'EOF'
name: 'genomics_dwh'
version: '1.0.0'
profile: 'genomics_dwh'

# These configurations specify where dbt should look for different types of files.
# The `model-paths` config, for example, states that models in this project can be
# found in the "models/" directory. You probably won't need to change these!
model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:         # directories to be removed by `dbt clean`
  - "target"
  - "dbt_packages"

# Configuring models
# Full documentation: https://docs.getdbt.com/docs/configuring-models
models:
  genomics_dwh:
    staging:
      +materialized: view
      +tags: ["bronze", "staging"]
    intermediate:
      +materialized: table
      +tags: ["silver", "intermediate"]
    marts:
      +materialized: table
      +tags: ["gold", "marts"]
      core:
        fct_variant_observation:
          +materialized: incremental
          +unique_key: ['sample_id_1kg', 'variant_key']
          +on_schema_change: 'append_new_columns'
        fct_mrd_test:
          +materialized: incremental
          +unique_key: 'test_sk'

EOF

# create macros/apply_clustering.sql
cat > macros/apply_clustering.sql <<'EOF'
{# Returns the right config block for the current target — Snowflake gets cluster_by,
   DuckDB gets nothing (we handle ordering in the model SQL via ORDER BY). #}
{% macro apply_clustering(cluster_cols) %}
  {% if target.type == 'snowflake' %}
    {{ return(config(cluster_by=cluster_cols)) }}
  {% endif %}
{% endmacro %}
EOF

# create models/marts/core/dim_date.sql
cat > models/marts/core/dim_date.sql <<'EOF'
{{ config(materialized='table') }}

with date_spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2015-01-01' as date)",
        end_date="cast('2030-12-31' as date)"
    ) }}
)

select
    cast(date_day as date) as date_sk,
    cast(date_day as date) as full_date,
    extract(year from date_day) as year,
    extract(quarter from date_day) as quarter,
    extract(month from date_day) as month_num,
    extract(day from date_day) as day_of_month,
    extract(dow from date_day) as day_of_week_num,
    strftime(date_day, '%A') as day_of_week_name,
    case when extract(dow from date_day) in (0, 6) then false else true end as is_business_day
from date_spine
EOF

# create snapshots/snap_dim_patient.sql
cat > snapshots/snap_dim_patient.sql <<'EOF'
{% snapshot snap_dim_patient %}

    {{
        config(
          target_schema='snapshots',
          unique_key='patient_id',
          strategy='check',
          check_cols=['tumor_type', 'stage_at_diagnosis', 'trial_id', 'treatment_arm']
        )
    }}

    select
        patient_id,
        sample_id_1kg,
        tumor_type,
        stage_at_diagnosis,
        age_at_diagnosis,
        sex_at_birth,
        ancestry_super_population,
        ancestry_population_code,
        diagnosis_date,
        primary_surgery_date,
        trial_id,
        treatment_arm,
        consented_for_research
    from {{ ref('int_patients__panel_designed') }}

{% endsnapshot %}
EOF

# run the snapshot (builds the SCD-2 history table)
dbt snapshot
# 15:41:13  Found 75 data tests, 13 models, 1 snapshot, 9 sources, 604 macros
# ...
# 15:41:13  Finished running 1 snapshot in 0 hours 0 minutes and 0.12 seconds (0.12s).
# 15:41:13  
# 15:41:13  Completed successfully

# create models/marts/core/dim_patient.sql
cat > models/marts/core/dim_patient.sql <<'EOF'
{{ config(materialized='table') }}

with snap as (
    select * from {{ ref('snap_dim_patient') }}
)

select
    {{ make_surrogate_key(['patient_id', 'dbt_valid_from']) }} as patient_sk,
    patient_id,
    sample_id_1kg,
    tumor_type,
    stage_at_diagnosis,
    age_at_diagnosis,
    sex_at_birth,
    ancestry_super_population,
    ancestry_population_code,
    diagnosis_date,
    primary_surgery_date,
    trial_id,
    treatment_arm,
    consented_for_research,
    dbt_valid_from as eff_from,
    coalesce(dbt_valid_to, cast('9999-12-31' as date)) as eff_to,
    dbt_valid_to is null as is_current
from snap
EOF

# create models/marts/core/dim_variant.sql
cat > models/marts/core/dim_variant.sql <<'EOF'
{{ config(
    materialized='table',
    post_hook=[
      "create index if not exists idx_dim_variant_key on {{ this }} (variant_key)",
      "create index if not exists idx_dim_variant_rsid on {{ this }} (rsid)"
    ]
) }}

with annotated as (
    select * from {{ ref('int_variants__annotated') }}
),

-- int_variants__annotated has multiple rows per variant_key from two fan-out sources:
--   1. Genes overlap — one variant can sit inside multiple gene definitions
--   2. ClinVar has multiple submissions per variant — different labs, conflicting calls
-- The dimension is variant-scoped, not (variant × gene × clinvar)-scoped, so we collapse
-- to one row per variant_key here. If "all overlapping genes" is ever needed downstream,
-- build a bridge_variant_gene model — don't denormalize the dimension.
deduped as (
    select *
    from annotated
    qualify row_number() over (
        partition by variant_key
        order by
            -- Prefer rows with gene info filled in
            case when gene_symbol is not null then 0 else 1 end,
            -- Prefer rows with ClinVar info filled in
            case when clinvar_significance is not null then 0 else 1 end,
            -- Stable tiebreaks so re-runs are deterministic
            gene_symbol nulls last,
            clinvar_review_status nulls last
    ) = 1
)

select
    {{ make_surrogate_key(['variant_key']) }} as variant_sk,
    variant_key,
    chromosome,
    position,
    ref_allele,
    alt_allele,
    variant_type,
    gene_symbol,
    ensembl_id,
    biotype,
    rsid,
    clinvar_significance,
    clinvar_disease_names,
    clinvar_review_status
from deduped
EOF

# create models/marts/core/dim_gene.sql
cat > models/marts/core/dim_gene.sql <<'EOF'
{{ config(materialized='table') }}

select distinct
    {{ make_surrogate_key(['ensembl_id']) }} as gene_sk,
    ensembl_id,
    gene_symbol,
    chromosome,
    gene_start,
    gene_end,
    biotype,
    case when gene_symbol in (
        -- Tiny seed list of cancer genes for chr22; expand using COSMIC Cancer Gene Census
        'NF2', 'CHEK2', 'EWSR1', 'BCR', 'PDGFB', 'EP300', 'SMARCB1'
    ) then true else false end as is_cancer_gene
from {{ ref('stg_ref__genes') }}
EOF

# create models/marts/core/dim_population.sql
cat > models/marts/core/dim_population.sql <<'EOF'
{{ config(materialized='table') }}

select distinct
    {{ make_surrogate_key(['population_code']) }} as population_sk,
    super_population,
    population_code,
    case super_population
        when 'AFR' then 'African'
        when 'AMR' then 'Admixed American'
        when 'EAS' then 'East Asian'
        when 'EUR' then 'European'
        when 'SAS' then 'South Asian'
    end as super_population_name
from {{ ref('stg_1kg__samples') }}
EOF

# create models/marts/core/dim_panel.sql
cat > models/marts/core/dim_panel.sql <<'EOF'
{{ config(materialized='table') }}

select
    {{ make_surrogate_key(['panel_id']) }}     as panel_sk,
    panel_id,
    patient_id,
    panel_design_date,
    panel_size
from (
    select distinct panel_id, patient_id, panel_design_date, panel_size
    from {{ ref('int_patients__panel_designed') }}
    where panel_id is not null
)
EOF

# create models/marts/core/fct_variant_observation.sql
cat > models/marts/core/fct_variant_observation.sql <<'EOF'
{{ apply_clustering(['chromosome', 'cast(position / 1000000 as integer)']) }}

{{ config(
    materialized='incremental',
    unique_key=['sample_id_1kg', 'variant_key'],
    on_schema_change='append_new_columns'
) }}

with variants as (
    select * from {{ ref('stg_1kg__variants') }}
    {% if is_incremental() %}
      -- Only pick up new load_ids since the last run
      where load_id not in (select distinct load_id from {{ this }})
    {% endif %}
),

variant_dim as (
    select
        variant_sk,
        variant_key
    from {{ ref('dim_variant') }}
),

patient_dim as (
    select
        patient_sk,
        sample_id_1kg
    from {{ ref('dim_patient') }}
    where is_current
),

joined as (
    select
        {{ make_surrogate_key(['v.sample_id', 'v.variant_key']) }} as observation_sk,
        v.sample_id as sample_id_1kg,
        p.patient_sk,
        d.variant_sk,
        v.variant_key,
        v.chromosome,
        v.position,
        v.ref_allele,
        v.alt_allele,
        v.variant_type,
        v.genotype,
        v.read_depth,
        v.variant_allele_count,
        v.variant_allele_freq,
        v.quality,
        v.filter_status,
        v.load_id,
        v.ingested_at
    from variants as v
    left join variant_dim as d on v.variant_key = d.variant_key
    left join patient_dim as p on v.sample_id = p.sample_id_1kg
)

select * from joined
{% if target.type == 'duckdb' %}
order by chromosome, position
{% endif %}
EOF

# create models/marts/core/fct_mrd_test.sql
cat > models/marts/core/fct_mrd_test.sql <<'EOF'
{{ apply_clustering(['test_date', 'patient_sk']) }}

{{ config(
    materialized='incremental',
    unique_key='test_sk'
) }}

with tests as (
    select * from {{ ref('int_mrd__test_with_panel') }}
    {% if is_incremental() %}
      where test_id not in (select test_id from {{ this }})
    {% endif %}
),

patients as (
    select
        patient_sk,
        patient_id
    from {{ ref('dim_patient') }}
    where is_current
),

panels as (
    select
        panel_sk,
        panel_id
    from {{ ref('dim_panel') }}
)

select
    {{ make_surrogate_key(['t.test_id']) }} as test_sk,
    t.test_id,
    p.patient_sk,
    pn.panel_sk,
    t.test_date,
    t.test_sequence_number,
    t.days_since_surgery,
    t.is_positive,
    t.mtm_per_ml,
    t.variants_detected_count,
    t.max_vaf_blood,
    t.avg_detected_vaf_blood,
    t.tumor_type,
    t.stage_at_diagnosis,
    t.trial_id,
    t.treatment_arm
from tests as t
left join patients as p on t.patient_id = p.patient_id
left join panels as pn on t.panel_id = pn.panel_id
{% if target.type == 'duckdb' %}
order by test_date, p.patient_sk
{% endif %}
EOF

# create models/marts/core/fct_mrd_detection.sql
cat > models/marts/core/fct_mrd_detection.sql <<'EOF'
{{ config(materialized='table') }}

with detections as (
    select * from {{ ref('stg_synth__mrd_detections') }}
),

tests as (
    select
        test_sk,
        test_id
    from {{ ref('fct_mrd_test') }}
),

variants as (
    select
        variant_sk,
        variant_key
    from {{ ref('dim_variant') }}
),

patients as (
    select
        patient_sk,
        patient_id
    from {{ ref('dim_patient') }}
    where is_current
)

select
    {{ make_surrogate_key(['detection_id']) }} as detection_sk,
    d.detection_id,
    t.test_sk,
    v.variant_sk,
    p.patient_sk,
    cast(d.vaf_blood as double) as vaf_blood,
    cast(d.is_detected as boolean) as is_detected
from detections as d
left join tests as t on d.test_id = t.test_id
left join variants as v on d.variant_key = v.variant_key
left join patients as p on d.patient_id = p.patient_id
order by t.test_sk
EOF

# create models/marts/core/fct_clinical_event.sql
cat > models/marts/core/fct_clinical_event.sql <<'EOF'
{{ apply_clustering(['event_date', 'patient_sk']) }}
{{ config(materialized='table') }}

with events as (
    select * from {{ ref('stg_synth__clinical_events') }}
),

patients as (
    select
        patient_sk,
        patient_id
    from {{ ref('dim_patient') }}
    where is_current
)

select
    {{ make_surrogate_key(['e.event_id']) }} as event_sk,
    e.event_id,
    p.patient_sk,
    cast(e.event_date as date) as event_date,
    e.event_type,
    e.event_subtype,
    e.regimen,
    e.outcome
from events as e
left join patients as p on e.patient_id = p.patient_id
{% if target.type == 'duckdb' %}
order by event_date, p.patient_sk
{% endif %}
EOF

# create models/marts/clinical/mart_clin__patient_timeline.sql
cat > models/marts/clinical/mart_clin__patient_timeline.sql <<'EOF'
{{ config(materialized='table') }}

with patients as (
    select * from {{ ref('dim_patient') }} where is_current
),

tests_summary as (
    select
        patient_sk,
        min(test_date) filter (where is_positive)            as first_positive_date,
        sum(case when is_positive then 1 else 0 end)         as positive_test_count,
        count(*)                                              as total_test_count,
        max(test_date)                                        as last_test_date
    from {{ ref('fct_mrd_test') }}
    group by 1
),

recurrence as (
    select patient_sk, min(event_date) as first_recurrence_date
    from {{ ref('fct_clinical_event') }}
    where event_type = 'recurrence'
    group by 1
),

landmark_status as (
    -- For each landmark (90/180/365/730 days post-surgery), find that patient's
    -- nearest test within +/- 30 days and call MRD status from it.
    select
        t.patient_sk,
        max(case when t.days_since_surgery between 60  and 120  then t.is_positive end) as mrd_status_d90,
        max(case when t.days_since_surgery between 150 and 210  then t.is_positive end) as mrd_status_d180,
        max(case when t.days_since_surgery between 335 and 395  then t.is_positive end) as mrd_status_d365,
        max(case when t.days_since_surgery between 700 and 760  then t.is_positive end) as mrd_status_d730
    from {{ ref('fct_mrd_test') }} t
    group by 1
)

select
    p.patient_sk,
    p.patient_id,
    p.tumor_type,
    p.stage_at_diagnosis,
    p.age_at_diagnosis,
    p.sex_at_birth,
    p.ancestry_super_population,
    p.diagnosis_date,
    p.primary_surgery_date,
    p.trial_id,
    p.treatment_arm,
    -- MRD trajectory summary
    ts.first_positive_date,
    ts.positive_test_count,
    ts.total_test_count,
    ts.last_test_date,
    -- Landmark statuses
    ls.mrd_status_d90,
    ls.mrd_status_d180,
    ls.mrd_status_d365,
    ls.mrd_status_d730,
    -- Outcomes
    r.first_recurrence_date,
    case when r.first_recurrence_date is not null then true else false end as has_recurred,
    case when r.first_recurrence_date is not null
         then date_diff('day', p.primary_surgery_date, r.first_recurrence_date)
         end as days_to_recurrence,
    case when ts.first_positive_date is not null and r.first_recurrence_date is not null
         then date_diff('day', ts.first_positive_date, r.first_recurrence_date)
         end as mrd_lead_time_days
from patients as p
left join tests_summary as ts on p.patient_sk = ts.patient_sk
left join landmark_status as ls on p.patient_sk = ls.patient_sk
left join recurrence as r on p.patient_sk = r.patient_sk
EOF

# create models/marts/pharma/mart_pharma__cohort_extract.sql
cat > models/marts/pharma/mart_pharma__cohort_extract.sql <<'EOF'
{{ config(materialized='table') }}

with consented_only as (
    select * from {{ ref('mart_clin__patient_timeline') }}
    where patient_sk in (
        select patient_sk from {{ ref('dim_patient') }}
        where is_current and consented_for_research = true
    )
)

select
    -- Mask the natural patient_id; surrogate key is opaque enough
    md5(patient_sk) as patient_sk_masked,
    tumor_type,
    stage_at_diagnosis,
    age_at_diagnosis,
    sex_at_birth,
    ancestry_super_population,
    trial_id,
    treatment_arm,
    -- Outcome columns pharma cares about
    mrd_status_d90,
    mrd_status_d180,
    mrd_status_d365,
    has_recurred,
    days_to_recurrence,
    mrd_lead_time_days,
    case when has_recurred and days_to_recurrence <= 730 then true else false end as recurrence_within_2yr,
    -- Censoring info
    last_test_date,
    case when has_recurred then 'event' else 'censored' end as event_status
from consented_only
EOF

# create models/marts/_marts__models.yml
cat > models/marts/_marts__models.yml <<'EOF'
version: 2

models:
  - name: dim_patient
    columns:
      - name: patient_sk
        tests: [not_null, unique]
      - name: is_current
        tests: [not_null]

  - name: dim_variant
    columns:
      - name: variant_sk
        tests: [not_null, unique]
      - name: variant_key
        tests: [not_null]

  - name: fct_variant_observation
    columns:
      - name: observation_sk
        tests: [not_null, unique]
      - name: patient_sk
        tests:
          - relationships:
              arguments:
                to: ref('dim_patient')
                field: patient_sk
      - name: variant_sk
        tests:
          - relationships:
              arguments:
                to: ref('dim_variant')
                field: variant_sk

  - name: fct_mrd_test
    columns:
      - name: test_sk
        tests: [not_null, unique]
      - name: patient_sk
        tests:
          - relationships:
              arguments:
                to: ref('dim_patient')
                field: patient_sk

  - name: mart_clin__patient_timeline
    columns:
      - name: patient_sk
        tests: [not_null, unique]

  - name: mart_pharma__cohort_extract
    columns:
      - name: patient_sk_masked
        tests: [not_null]
EOF

# build the whole DAG
dbt deps
dbt build
# 15:56:39  Running with dbt=1.11.11
# 15:56:40  Registered adapter: duckdb=1.10.1
# There are 1 unused configuration paths:
# - models.genomics_dwh.example
# 15:56:40  Found 91 data tests, 24 models, 1 snapshot, 9 sources, 604 macros
# ...
# 15:56:43  115 of 116 PASS relationships_fct_variant_observation_variant_sk__variant_sk__ref_dim_variant_  [PASS in 0.05s]
# 15:56:43  116 of 116 PASS unique_fct_variant_observation_observation_sk .................. [PASS in 0.05s]
# 15:56:43  
# 15:56:43  Finished running 2 incremental models, 1 snapshot, 13 table models, 91 data tests, 9 view models in 0 hours 0 minutes and 2.69 seconds (2.69s).
# 15:56:43  
# 15:56:43  Completed successfully

# verify database
duckdb ../warehouse.duckdb <<'SQL'
-- "MRD positivity rate at landmark by stage" (no joins!)
SELECT stage_at_diagnosis,
       round(100.0 * sum(case when mrd_status_d90 then 1 else 0 end) / count(*), 1) AS pct_pos_d90,
       round(100.0 * sum(case when mrd_status_d365 then 1 else 0 end) / count(*), 1) AS pct_pos_d365,
       count(*) AS n
FROM main.mart_clin__patient_timeline
GROUP BY 1
ORDER BY 1;

-- "Lead time from MRD+ to recurrence"
SELECT stage_at_diagnosis,
       avg(mrd_lead_time_days) AS avg_lead_days,
       count(*) FILTER (WHERE mrd_lead_time_days IS NOT NULL) AS n_with_lead_time
FROM main.mart_clin__patient_timeline
WHERE has_recurred
GROUP BY 1;
SQL

# ┌────────────────────┬─────────────┬──────────────┬───────┐
# │ stage_at_diagnosis │ pct_pos_d90 │ pct_pos_d365 │   n   │
# │      varchar       │   double    │    double    │ int64 │
# ├────────────────────┼─────────────┼──────────────┼───────┤
# │ I                  │         0.0 │          0.0 │    17 │
# │ II                 │         0.0 │         22.2 │     9 │
# │ III                │         0.0 │         15.4 │    13 │
# │ IV                 │        36.4 │         36.4 │    11 │
# └────────────────────┴─────────────┴──────────────┴───────┘
# ┌────────────────────┬────────────────────┬──────────────────┐
# │ stage_at_diagnosis │   avg_lead_days    │ n_with_lead_time │
# │      varchar       │       double       │      int64       │
# ├────────────────────┼────────────────────┼──────────────────┤
# │ III                │              300.0 │               12 │
# │ IV                 │ 106.36363636363636 │               11 │
# │ I                  │              472.5 │                4 │
# │ II                 │              360.0 │                3 │
# └────────────────────┴────────────────────┴──────────────────┘

# generate docs
dbt docs generate

# serve docs and browse lineage graph (opens at http://localhost:8080)
dbt docs serve
# CTRL+C to stop

# run linter and fix (from dbt project dir)
sqlfluff lint macros models/marts snapshots
# if errors: sqlfluff fix macros models/marts snapshots

# commit progress (from repo root)
cd ..
git add genomics_dwh/macros/ genomics_dwh/models/marts/ genomics_dwh/snapshots/ genomics_dwh/*.yml
git commit -m "Phase 6: Gold marts — dimensions, facts, OBT marts, SCD2 snapshot"


####################### ******************* #########################
#         CELEBRATE!!! 
####################### ******************* #########################
```
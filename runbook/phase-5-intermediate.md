# Phase 5 - Intermediate layer
**Goal:** join staging models into business-meaningful intermediate tables. This is where you write the genomic-clinical joins for the first time, where SCD logic gets stamped, and where custom dbt tests start catching the business rules synth data has to obey.

## Commands (step-by-step)
```bash
#######################################################
# 5. INTERMEDIATE LAYER
# - join staging models into business-meaningful intermediate tables. 
#   This is where you write genomic-clinical joins for the first time,
#   where SCD logic gets stamped, and where custom dbt tests start catching
#   the business rules synth data has to obey.
#
# - reusable macros
# - join tables (variants, panels, MRD tests)
# - custom tests
#######################################################

# create genomics_dwh/macros/make_variant_key.sql
cat > genomics_dwh/macros/make_variant_key.sql <<'EOF'
{% macro make_variant_key(chrom='chromosome', pos='position', ref='ref_allele', alt='alt_allele') %}
    {{ chrom }} || '_' || {{ pos }} || '_' || {{ ref }} || '_' || {{ alt }}
{% endmacro %}
EOF

# create genomics_dwh/macros/make_surrogate_key.sql
cat > genomics_dwh/macros/make_surrogate_key.sql <<'EOF'
{# Wraps dbt_utils.generate_surrogate_key but stays portable if you swap utils packages later. #}
{% macro make_surrogate_key(columns) %}
    md5(
      {% for col in columns -%}
        coalesce(cast({{ col }} as varchar), '_NULL_')
        {%- if not loop.last %} || '_' || {% endif %}
      {%- endfor %}
    )
{% endmacro %}
EOF

# change to dbt project dir
cd genomics_dwh
mkdir -p models/intermediate/{genomic,clinical,mrd}

# create models/intermediate/genomic/int_variants__annotated.sql
cat > models/intermediate/genomic/int_variants__annotated.sql <<'EOF'
{{ config(materialized='table') }}

with variants as (
    select
        variant_key,
        chromosome,
        position,
        ref_allele,
        alt_allele,
        variant_type
    from {{ ref('stg_1kg__variants') }}
    -- Distinct because the same variant appears across many samples in the variants
    -- table; for the gene/clinvar dimension we only care about the variant identity.
    group by 1, 2, 3, 4, 5, 6
),

genes as (
    select
        gene_symbol,
        ensembl_id,
        chromosome,
        gene_start,
        gene_end,
        biotype
    from {{ ref('stg_ref__genes') }}
),

clinvar as (
    select
        variant_key,
        rsid,
        clinvar_significance,
        clinvar_disease_names,
        clinvar_review_status
    from {{ ref('stg_ref__clinvar') }}
),

variant_to_gene as (
    select
        v.variant_key,
        v.chromosome,
        v.position,
        v.ref_allele,
        v.alt_allele,
        v.variant_type,
        g.gene_symbol,
        g.ensembl_id,
        g.biotype
    from variants as v
    left join genes as g
        on
            v.chromosome = g.chromosome
            and v.position between g.gene_start and g.gene_end
),

with_clinvar as (
    select
        vg.*,
        cv.rsid,
        cv.clinvar_significance,
        cv.clinvar_disease_names,
        cv.clinvar_review_status
    from variant_to_gene as vg
    left join clinvar as cv on vg.variant_key = cv.variant_key
)

select * from with_clinvar
EOF

# create models/intermediate/clinical/int_patients__panel_designed.sql
cat > models/intermediate/clinical/int_patients__panel_designed.sql <<'EOF'
{{ config(materialized='table') }}

with patients as (
    select * from {{ ref('stg_synth__patients') }}
),

panels as (
    select
        patient_id,
        panel_id,
        variant_key,
        chromosome,
        position,
        ref_allele,
        alt_allele,
        cast(simulated_tumor_vaf as double) as simulated_tumor_vaf,
        cast(panel_design_date as date) as panel_design_date,
        variant_index
    from {{ ref('stg_synth__panels') }}
),

panel_summary as (
    select
        panel_id,
        patient_id,
        max(panel_design_date) as panel_design_date,
        count(*) as panel_size
    from panels
    group by 1, 2
)

select
    p.*,
    ps.panel_id,
    ps.panel_design_date,
    ps.panel_size
from patients as p
left join panel_summary as ps on p.patient_id = ps.patient_id
EOF

# create models/intermediate/mrd/int_mrd__test_with_panel.sql
cat > models/intermediate/mrd/int_mrd__test_with_panel.sql <<'EOF'
{{ config(materialized='table') }}

with tests as (
    select * from {{ ref('stg_synth__mrd_tests') }}
),

detections as (
    select * from {{ ref('stg_synth__mrd_detections') }}
),

patients as (
    select
        patient_id,
        primary_surgery_date,
        tumor_type,
        stage_at_diagnosis,
        trial_id,
        treatment_arm
    from {{ ref('stg_synth__patients') }}
),

tests_with_clinical as (
    select
        t.test_id,
        t.patient_id,
        t.panel_id,
        cast(t.test_date as date) as test_date,
        t.test_sequence_number,
        t.days_since_surgery,
        cast(t.is_positive as boolean) as is_positive,
        cast(t.mtm_per_ml as double) as mtm_per_ml,
        p.tumor_type,
        p.stage_at_diagnosis,
        p.trial_id,
        p.treatment_arm,
        cast(p.primary_surgery_date as date) as primary_surgery_date
    from tests as t
    inner join patients as p on t.patient_id = p.patient_id
),

variants_detected_per_test as (
    select
        test_id,
        sum(case when is_detected then 1 else 0 end) as variants_detected_count,
        max(vaf_blood) as max_vaf_blood,
        avg(case when is_detected then vaf_blood end) as avg_detected_vaf_blood
    from detections
    group by 1
)

select
    twc.*,
    coalesce(vdpt.variants_detected_count, 0) as variants_detected_count,
    vdpt.max_vaf_blood,
    vdpt.avg_detected_vaf_blood
from tests_with_clinical as twc
left join variants_detected_per_test as vdpt on twc.test_id = vdpt.test_id
EOF

# create models/intermediate/_intermediate__models.yml (schemas and tests)
cat > models/intermediate/_intermediate__models.yml <<'EOF'
version: 2

models:
  - name: int_variants__annotated
    description: "Distinct variants annotated with overlapping gene and ClinVar significance."
    columns:
      - name: variant_key
        tests: [not_null]
      - name: variant_type
        tests:
          - accepted_values:
              arguments:
                values: ['SNV', 'INSERTION', 'DELETION', 'MNP', 'OTHER']

  - name: int_patients__panel_designed
    description: "Patients enriched with their personalized panel summary."
    columns:
      - name: patient_id
        tests: [not_null, unique]
      - name: panel_size
        tests:
          - dbt_utils.accepted_range:
              arguments:
                min_value: 12
                max_value: 20

  - name: int_mrd__test_with_panel
    description: "MRD tests joined to clinical context and per-test detection summary."
    columns:
      - name: test_id
        tests: [not_null, unique]
      - name: variants_detected_count
        tests:
          - dbt_utils.accepted_range:
              arguments:
                min_value: 0
                max_value: 16
EOF

# create tests/assert_no_mrd_pos_before_surgery.sql (custom test)
cat > tests/assert_no_mrd_pos_before_surgery.sql <<'EOF'
-- Returns rows that VIOLATE the rule (the test fails if it returns any rows)
select t.test_id, t.patient_id, t.test_date, t.primary_surgery_date
from {{ ref('int_mrd__test_with_panel') }} t
where t.is_positive
  and t.test_date < t.primary_surgery_date
EOF

# create tests/assert_test_dates_monotonic_per_patient.sql (custom test)
cat > tests/assert_test_dates_monotonic_per_patient.sql <<'EOF'
with ordered as (
    select
        patient_id,
        test_date,
        lag(test_date) over (partition by patient_id order by test_date) as prev_test_date
    from {{ ref('int_mrd__test_with_panel') }}
)
select *
from ordered
where prev_test_date is not null
  and test_date <= prev_test_date
EOF

# create tests/assert_panel_variants_in_germline.sql (custom test)
cat > tests/assert_panel_variants_in_germline.sql <<'EOF'
-- Every panel variant must exist in that patient's germline VCF
with panel_variants as (
    select
        p.patient_id,
        pt.sample_id_1kg,
        p.variant_key
    from {{ ref('stg_synth__panels') }} as p
    inner join {{ ref('stg_synth__patients') }} as pt on p.patient_id = pt.patient_id
),

germline_variants as (
    select
        sample_id,
        variant_key
    from {{ ref('stg_1kg__variants') }}
)

select pv.*
from panel_variants as pv
left join germline_variants as gv
    on
        pv.sample_id_1kg = gv.sample_id
        and pv.variant_key = gv.variant_key
where gv.variant_key is null
EOF

# build and verify
dbt build --select intermediate
# Expect: 3 tables built, all tests pass

# If a test fails, look at the failing rows:
dbt test --select assert_no_mrd_pos_before_surgery --store-failures
duckdb ../warehouse.duckdb -c "SELECT * FROM main_dbt_test__audit.assert_no_mrd_pos_before_surgery LIMIT 10"

# run linter and fix sql if needed
sqlfluff lint models tests
sqlfluff fix models tests
# if fix required, re-test build: dbt build --select intermediate

# commit progress
cd ..
git add genomics_dwh/macros/ genomics_dwh/models/intermediate/ genomics_dwh/tests/
git commit -m "Phase 5: intermediate layer with annotated variants, panels, MRD test joins"
```
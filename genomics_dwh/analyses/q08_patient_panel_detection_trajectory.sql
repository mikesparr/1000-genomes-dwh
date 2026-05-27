-- analyses/q08_patient_panel_detection_trajectory.sql
--
-- Persona: Genomic Researcher
-- Question: "Variants in panel for patient PT-HG00096 detected in their last
--            3 blood draws"
--
-- Demonstrates: patient-scoped pruning at the fact level. The first CTE filters
-- to a single patient_sk (1 of 28 in this slice, or 1 of 30k at production scale).
-- Downstream joins to fct_mrd_detection and dim_variant operate on the tiny
-- already-filtered result set, so the query runs in milliseconds against any
-- properly-clustered warehouse.
--
-- The output shape is the "detection heatmap" researchers love: rows = panel
-- variants × tests, columns = detection / VAF. Useful for understanding which
-- variants in the panel are most informative for THIS patient's recurrence dynamics.
--
-- Run: dbt show --select q08_patient_panel_detection_trajectory --limit 50

with target_patient as (
    -- Substitute any patient_id of interest
    select
        patient_sk,
        patient_id
    from {{ ref('dim_patient') }}
    where
        patient_id = 'PT-HG00096'
        and is_current
),

last_three_tests as (
    select
        t.test_sk,
        t.test_id,
        t.test_date,
        t.test_sequence_number,
        t.is_positive,
        t.mtm_per_ml,
        row_number() over (
            partition by t.patient_sk
            order by t.test_date desc
        ) as rn_recent
    from {{ ref('fct_mrd_test') }} as t
    inner join target_patient as tp on t.patient_sk = tp.patient_sk
    qualify rn_recent <= 3
)

select
    v.gene_symbol,
    v.variant_key,
    v.chromosome,
    v.position,
    v.ref_allele,
    v.alt_allele,
    v.clinvar_significance,
    l.test_sequence_number,
    l.test_date,
    l.is_positive as test_is_positive,
    d.vaf_blood,
    d.is_detected
from last_three_tests as l
inner join {{ ref('fct_mrd_detection') }} as d on l.test_sk = d.test_sk
inner join {{ ref('dim_variant') }} as v on d.variant_sk = v.variant_sk
order by l.test_sequence_number, v.gene_symbol nulls last, v.position

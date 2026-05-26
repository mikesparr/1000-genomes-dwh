

with tests as (
    select * from "ci_warehouse"."main"."stg_synth__mrd_tests"
),

detections as (
    select * from "ci_warehouse"."main"."stg_synth__mrd_detections"
),

patients as (
    select
        patient_id,
        primary_surgery_date,
        tumor_type,
        stage_at_diagnosis,
        trial_id,
        treatment_arm
    from "ci_warehouse"."main"."stg_synth__patients"
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
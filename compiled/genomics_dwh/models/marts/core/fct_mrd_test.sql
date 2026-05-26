
  




with tests as (
    select * from "ci_warehouse"."main"."int_mrd__test_with_panel"
    
),

patients as (
    select
        patient_sk,
        patient_id
    from "ci_warehouse"."main"."dim_patient"
    where is_current
),

panels as (
    select
        panel_sk,
        panel_id
    from "ci_warehouse"."main"."dim_panel"
)

select
    
    md5(
      coalesce(cast(t.test_id as varchar), '_NULL_')
    )
 as test_sk,
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

    order by test_date, p.patient_sk



with patients as (
    select * from "ci_warehouse"."main"."dim_patient"
    where is_current
),

tests_summary as (
    select
        patient_sk,
        min(test_date) filter (where is_positive) as first_positive_date,
        sum(case when is_positive then 1 else 0 end) as positive_test_count,
        count(*) as total_test_count,
        max(test_date) as last_test_date
    from "ci_warehouse"."main"."fct_mrd_test"
    group by 1
),

recurrence as (
    select
        patient_sk,
        min(event_date) as first_recurrence_date
    from "ci_warehouse"."main"."fct_clinical_event"
    where event_type = 'recurrence'
    group by 1
),

landmark_status as (
    -- For each landmark (90/180/365/730 days post-surgery), find that patient's
    -- nearest test within +/- 30 days and call MRD status from it.
    select
        t.patient_sk,
        max(case when t.days_since_surgery between 60 and 120 then t.is_positive end) as mrd_status_d90,
        max(case when t.days_since_surgery between 150 and 210 then t.is_positive end) as mrd_status_d180,
        max(case when t.days_since_surgery between 335 and 395 then t.is_positive end) as mrd_status_d365,
        max(case when t.days_since_surgery between 700 and 760 then t.is_positive end) as mrd_status_d730
    from "ci_warehouse"."main"."fct_mrd_test" as t
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
    coalesce(r.first_recurrence_date is not null, false) as has_recurred,
    case
        when r.first_recurrence_date is not null
            then date_diff('day', p.primary_surgery_date, r.first_recurrence_date)
    end as days_to_recurrence,
    case
        when ts.first_positive_date is not null and r.first_recurrence_date is not null
            then date_diff('day', ts.first_positive_date, r.first_recurrence_date)
    end as mrd_lead_time_days
from patients as p
left join tests_summary as ts on p.patient_sk = ts.patient_sk
left join landmark_status as ls on p.patient_sk = ls.patient_sk
left join recurrence as r on p.patient_sk = r.patient_sk
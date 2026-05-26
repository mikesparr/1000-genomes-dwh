

with consented_only as (
    select * from "ci_warehouse"."main"."mart_clin__patient_timeline"
    where patient_sk in (
        select patient_sk from "ci_warehouse"."main"."dim_patient"
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
    coalesce(has_recurred and days_to_recurrence <= 730, false) as recurrence_within_2yr,
    -- Censoring info
    last_test_date,
    case when has_recurred then 'event' else 'censored' end as event_status
from consented_only
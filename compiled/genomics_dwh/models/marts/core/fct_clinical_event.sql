
  



with events as (
    select * from "ci_warehouse"."main"."stg_synth__clinical_events"
),

patients as (
    select
        patient_sk,
        patient_id
    from "ci_warehouse"."main"."dim_patient"
    where is_current
)

select
    
    md5(
      coalesce(cast(e.event_id as varchar), '_NULL_')
    )
 as event_sk,
    e.event_id,
    p.patient_sk,
    cast(e.event_date as date) as event_date,
    e.event_type,
    e.event_subtype,
    e.regimen,
    e.outcome
from events as e
left join patients as p on e.patient_id = p.patient_id

    order by event_date, p.patient_sk

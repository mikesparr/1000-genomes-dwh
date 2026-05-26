
    
    

with all_values as (

    select
        event_type as value_field,
        count(*) as n_records

    from "ci_warehouse"."main"."stg_synth__clinical_events"
    group by event_type

)

select *
from all_values
where value_field not in (
    'diagnosis','surgery','chemotherapy_start','recurrence','imaging','death'
)



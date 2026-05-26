
    
    

with child as (
    select patient_id as from_field
    from "ci_warehouse"."main"."stg_synth__clinical_events"
    where patient_id is not null
),

parent as (
    select patient_id as to_field
    from "ci_warehouse"."main"."stg_synth__patients"
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null




    
    

with child as (
    select test_id as from_field
    from "ci_warehouse"."main"."stg_synth__mrd_detections"
    where test_id is not null
),

parent as (
    select test_id as to_field
    from "ci_warehouse"."main"."stg_synth__mrd_tests"
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null



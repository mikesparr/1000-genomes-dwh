
    
    

with child as (
    select sample_id_1kg as from_field
    from "ci_warehouse"."main"."stg_synth__patients"
    where sample_id_1kg is not null
),

parent as (
    select sample_id as to_field
    from "ci_warehouse"."main"."stg_1kg__samples"
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null



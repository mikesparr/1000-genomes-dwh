
    
    

with child as (
    select variant_sk as from_field
    from "ci_warehouse"."main"."fct_variant_observation"
    where variant_sk is not null
),

parent as (
    select variant_sk as to_field
    from "ci_warehouse"."main"."dim_variant"
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null



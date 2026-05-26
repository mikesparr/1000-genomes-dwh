
    
    

with all_values as (

    select
        variant_type as value_field,
        count(*) as n_records

    from "ci_warehouse"."main"."int_variants__annotated"
    group by variant_type

)

select *
from all_values
where value_field not in (
    'SNV','INSERTION','DELETION','MNP','OTHER'
)



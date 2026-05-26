
    
    

with all_values as (

    select
        variant_type as value_field,
        count(*) as n_records

    from "ci_warehouse"."main"."stg_1kg__variants"
    group by variant_type

)

select *
from all_values
where value_field not in (
    'SNV','INSERTION','DELETION','MNP','OTHER'
)




    
    

with all_values as (

    select
        chromosome as value_field,
        count(*) as n_records

    from "ci_warehouse"."main"."stg_ref__genes"
    group by chromosome

)

select *
from all_values
where value_field not in (
    'chr22'
)



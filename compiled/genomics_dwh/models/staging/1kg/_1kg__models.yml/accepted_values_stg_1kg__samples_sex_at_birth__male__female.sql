
    
    

with all_values as (

    select
        sex_at_birth as value_field,
        count(*) as n_records

    from "ci_warehouse"."main"."stg_1kg__samples"
    group by sex_at_birth

)

select *
from all_values
where value_field not in (
    'male','female'
)



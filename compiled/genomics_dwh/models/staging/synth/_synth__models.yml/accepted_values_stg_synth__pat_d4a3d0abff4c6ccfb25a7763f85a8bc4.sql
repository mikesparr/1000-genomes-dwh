
    
    

with all_values as (

    select
        ancestry_super_population as value_field,
        count(*) as n_records

    from "ci_warehouse"."main"."stg_synth__patients"
    group by ancestry_super_population

)

select *
from all_values
where value_field not in (
    'AFR','AMR','EAS','EUR','SAS'
)



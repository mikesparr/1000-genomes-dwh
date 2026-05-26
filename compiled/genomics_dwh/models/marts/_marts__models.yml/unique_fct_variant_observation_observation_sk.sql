
    
    

select
    observation_sk as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."fct_variant_observation"
where observation_sk is not null
group by observation_sk
having count(*) > 1




    
    

select
    variant_sk as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."dim_variant"
where variant_sk is not null
group by variant_sk
having count(*) > 1



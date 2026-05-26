
    
    

select
    sample_id as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."stg_1kg__samples"
where sample_id is not null
group by sample_id
having count(*) > 1



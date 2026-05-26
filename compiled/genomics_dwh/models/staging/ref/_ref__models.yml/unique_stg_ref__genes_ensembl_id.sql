
    
    

select
    ensembl_id as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."stg_ref__genes"
where ensembl_id is not null
group by ensembl_id
having count(*) > 1



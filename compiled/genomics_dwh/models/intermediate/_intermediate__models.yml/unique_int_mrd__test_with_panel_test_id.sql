
    
    

select
    test_id as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."int_mrd__test_with_panel"
where test_id is not null
group by test_id
having count(*) > 1



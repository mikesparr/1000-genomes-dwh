
    
    

select
    test_id as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."stg_synth__mrd_tests"
where test_id is not null
group by test_id
having count(*) > 1



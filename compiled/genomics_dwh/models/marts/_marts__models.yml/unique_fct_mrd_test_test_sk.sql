
    
    

select
    test_sk as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."fct_mrd_test"
where test_sk is not null
group by test_sk
having count(*) > 1




    
    

select
    patient_sk as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."dim_patient"
where patient_sk is not null
group by patient_sk
having count(*) > 1



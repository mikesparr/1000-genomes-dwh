
    
    

select
    patient_id as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."int_patients__panel_designed"
where patient_id is not null
group by patient_id
having count(*) > 1



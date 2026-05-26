
    
    

select
    patient_id as unique_field,
    count(*) as n_records

from read_parquet('../bronze/raw_synth__patients.parquet')
where patient_id is not null
group by patient_id
having count(*) > 1




    
    



select patient_id
from read_parquet('../bronze/raw_synth__panels.parquet')
where patient_id is null



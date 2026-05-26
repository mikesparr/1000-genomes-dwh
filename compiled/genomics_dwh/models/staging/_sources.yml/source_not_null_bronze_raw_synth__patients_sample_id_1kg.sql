
    
    



select sample_id_1kg
from read_parquet('../bronze/raw_synth__patients.parquet')
where sample_id_1kg is null



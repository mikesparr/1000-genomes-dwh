
    
    



select variant_key
from read_parquet('../bronze/raw_synth__panels.parquet')
where variant_key is null



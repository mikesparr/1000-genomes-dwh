
    
    



select test_id
from read_parquet('../bronze/raw_synth__mrd_tests.parquet')
where test_id is null



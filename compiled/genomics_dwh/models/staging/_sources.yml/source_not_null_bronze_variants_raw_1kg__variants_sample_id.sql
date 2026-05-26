
    
    



select sample_id
from read_parquet('../bronze/raw_1kg__variants/**/*.parquet', hive_partitioning=true)
where sample_id is null



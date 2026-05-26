
    
    



select position
from read_parquet('../bronze/raw_1kg__variants/**/*.parquet', hive_partitioning=true)
where position is null



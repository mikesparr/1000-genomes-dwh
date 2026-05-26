
    
    



select sample
from read_parquet('../bronze/raw_1kg__samples.parquet')
where sample is null



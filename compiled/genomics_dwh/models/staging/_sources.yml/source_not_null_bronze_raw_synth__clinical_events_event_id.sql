
    
    



select event_id
from read_parquet('../bronze/raw_synth__clinical_events.parquet')
where event_id is null



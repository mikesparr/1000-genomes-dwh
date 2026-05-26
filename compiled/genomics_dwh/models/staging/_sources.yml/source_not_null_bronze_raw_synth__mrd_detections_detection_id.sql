
    
    



select detection_id
from read_parquet('../bronze/raw_synth__mrd_detections.parquet')
where detection_id is null



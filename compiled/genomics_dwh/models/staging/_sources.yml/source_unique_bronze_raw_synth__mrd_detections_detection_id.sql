
    
    

select
    detection_id as unique_field,
    count(*) as n_records

from read_parquet('../bronze/raw_synth__mrd_detections.parquet')
where detection_id is not null
group by detection_id
having count(*) > 1



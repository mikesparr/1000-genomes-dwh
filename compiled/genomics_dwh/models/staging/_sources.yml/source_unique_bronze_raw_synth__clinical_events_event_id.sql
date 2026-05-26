
    
    

select
    event_id as unique_field,
    count(*) as n_records

from read_parquet('../bronze/raw_synth__clinical_events.parquet')
where event_id is not null
group by event_id
having count(*) > 1



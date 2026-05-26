
    
    

select
    event_id as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."stg_synth__clinical_events"
where event_id is not null
group by event_id
having count(*) > 1



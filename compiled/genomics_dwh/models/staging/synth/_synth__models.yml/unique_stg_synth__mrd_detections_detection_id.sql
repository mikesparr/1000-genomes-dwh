
    
    

select
    detection_id as unique_field,
    count(*) as n_records

from "ci_warehouse"."main"."stg_synth__mrd_detections"
where detection_id is not null
group by detection_id
having count(*) > 1



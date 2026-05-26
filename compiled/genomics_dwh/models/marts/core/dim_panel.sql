

select
    
    md5(
      coalesce(cast(panel_id as varchar), '_NULL_')
    )
     as panel_sk,
    panel_id,
    patient_id,
    panel_design_date,
    panel_size
from (
    select distinct
        panel_id,
        patient_id,
        panel_design_date,
        panel_size
    from "ci_warehouse"."main"."int_patients__panel_designed"
    where panel_id is not null
)
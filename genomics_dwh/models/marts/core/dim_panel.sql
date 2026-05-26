{{ config(materialized='table') }}

select
    {{ make_surrogate_key(['panel_id']) }}     as panel_sk,
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
    from {{ ref('int_patients__panel_designed') }}
    where panel_id is not null
)

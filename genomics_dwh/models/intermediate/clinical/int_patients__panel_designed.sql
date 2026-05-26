{{ config(materialized='table') }}

with patients as (
    select * from {{ ref('stg_synth__patients') }}
),

panels as (
    select
        patient_id,
        panel_id,
        variant_key,
        chromosome,
        position,
        ref_allele,
        alt_allele,
        cast(simulated_tumor_vaf as double) as simulated_tumor_vaf,
        cast(panel_design_date as date) as panel_design_date,
        variant_index
    from {{ ref('stg_synth__panels') }}
),

panel_summary as (
    select
        panel_id,
        patient_id,
        max(panel_design_date) as panel_design_date,
        count(*) as panel_size
    from panels
    group by 1, 2
)

select
    p.*,
    ps.panel_id,
    ps.panel_design_date,
    ps.panel_size
from patients as p
left join panel_summary as ps on p.patient_id = ps.patient_id

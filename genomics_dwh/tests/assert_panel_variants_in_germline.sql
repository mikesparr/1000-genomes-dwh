-- Every panel variant must exist in that patient's germline VCF
with panel_variants as (
    select
        p.patient_id,
        pt.sample_id_1kg,
        p.variant_key
    from {{ ref('stg_synth__panels') }} as p
    inner join {{ ref('stg_synth__patients') }} as pt on p.patient_id = pt.patient_id
),

germline_variants as (
    select
        sample_id,
        variant_key
    from {{ ref('stg_1kg__variants') }}
)

select pv.*
from panel_variants as pv
left join germline_variants as gv
    on
        pv.sample_id_1kg = gv.sample_id
        and pv.variant_key = gv.variant_key
where gv.variant_key is null

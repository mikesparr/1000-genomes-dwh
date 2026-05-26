{{ apply_clustering(['test_date', 'patient_sk']) }}

{{ config(
    materialized='incremental',
    unique_key='test_sk'
) }}

with tests as (
    select * from {{ ref('int_mrd__test_with_panel') }}
    {% if is_incremental() %}
        where test_id not in (select test_id from {{ this }})
    {% endif %}
),

patients as (
    select
        patient_sk,
        patient_id
    from {{ ref('dim_patient') }}
    where is_current
),

panels as (
    select
        panel_sk,
        panel_id
    from {{ ref('dim_panel') }}
)

select
    {{ make_surrogate_key(['t.test_id']) }} as test_sk,
    t.test_id,
    p.patient_sk,
    pn.panel_sk,
    t.test_date,
    t.test_sequence_number,
    t.days_since_surgery,
    t.is_positive,
    t.mtm_per_ml,
    t.variants_detected_count,
    t.max_vaf_blood,
    t.avg_detected_vaf_blood,
    t.tumor_type,
    t.stage_at_diagnosis,
    t.trial_id,
    t.treatment_arm
from tests as t
left join patients as p on t.patient_id = p.patient_id
left join panels as pn on t.panel_id = pn.panel_id
{% if target.type == 'duckdb' %}
    order by test_date, p.patient_sk
{% endif %}

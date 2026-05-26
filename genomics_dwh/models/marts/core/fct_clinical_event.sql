{{ apply_clustering(['event_date', 'patient_sk']) }}
{{ config(materialized='table') }}

with events as (
    select * from {{ ref('stg_synth__clinical_events') }}
),

patients as (
    select
        patient_sk,
        patient_id
    from {{ ref('dim_patient') }}
    where is_current
)

select
    {{ make_surrogate_key(['e.event_id']) }} as event_sk,
    e.event_id,
    p.patient_sk,
    cast(e.event_date as date) as event_date,
    e.event_type,
    e.event_subtype,
    e.regimen,
    e.outcome
from events as e
left join patients as p on e.patient_id = p.patient_id
{% if target.type == 'duckdb' %}
    order by event_date, p.patient_sk
{% endif %}

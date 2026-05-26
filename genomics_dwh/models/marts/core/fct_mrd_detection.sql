{{ config(materialized='table') }}

with detections as (
    select * from {{ ref('stg_synth__mrd_detections') }}
),

tests as (
    select
        test_sk,
        test_id
    from {{ ref('fct_mrd_test') }}
),

variants as (
    select
        variant_sk,
        variant_key
    from {{ ref('dim_variant') }}
),

patients as (
    select
        patient_sk,
        patient_id
    from {{ ref('dim_patient') }}
    where is_current
)

select
    {{ make_surrogate_key(['detection_id']) }} as detection_sk,
    d.detection_id,
    t.test_sk,
    v.variant_sk,
    p.patient_sk,
    cast(d.vaf_blood as double) as vaf_blood,
    cast(d.is_detected as boolean) as is_detected
from detections as d
left join tests as t on d.test_id = t.test_id
left join variants as v on d.variant_key = v.variant_key
left join patients as p on d.patient_id = p.patient_id
order by t.test_sk

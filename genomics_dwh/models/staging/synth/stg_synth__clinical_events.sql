{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_synth__clinical_events') }}
),

renamed as (
    select
        event_id,
        patient_id,
        cast(event_date as date) as event_date,
        event_type,
        event_subtype,
        regimen,
        outcome,
        load_id,
        ingested_at
    from source
)

select * from renamed

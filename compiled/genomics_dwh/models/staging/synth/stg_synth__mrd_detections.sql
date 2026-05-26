

with source as (
    select * from read_parquet('../bronze/raw_synth__mrd_detections.parquet')
),

renamed as (
    select
        detection_id,
        test_id,
        patient_id,
        variant_key,
        cast(vaf_blood as double) as vaf_blood,
        cast(is_detected as boolean) as is_detected,
        load_id,
        ingested_at
    from source
)

select * from renamed
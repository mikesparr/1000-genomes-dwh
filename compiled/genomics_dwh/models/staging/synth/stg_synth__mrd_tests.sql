

with source as (
    select * from read_parquet('../bronze/raw_synth__mrd_tests.parquet')
),

renamed as (
    select
        test_id,
        patient_id,
        panel_id,
        cast(test_date as date) as test_date,
        cast(test_sequence_number as integer) as test_sequence_number,
        cast(days_since_surgery as integer) as days_since_surgery,
        cast(is_positive as boolean) as is_positive,
        cast(mtm_per_ml as double) as mtm_per_ml,
        load_id,
        ingested_at
    from source
)

select * from renamed
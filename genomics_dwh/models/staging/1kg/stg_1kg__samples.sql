{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_1kg__samples') }}
),

renamed as (
    select
        sample as sample_id,
        pop as population_code,
        super_pop as super_population,
        lower(gender) as sex_at_birth,
        load_id,
        ingested_at
    from source
)

select * from renamed

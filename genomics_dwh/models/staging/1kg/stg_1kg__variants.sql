{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze_variants', 'raw_1kg__variants') }}
),

renamed as (
    select
        sample_id,
        chromosome,
        cast(position as bigint) as position,
        ref_allele,
        alt_allele,
        chromosome || '_' || position || '_' || ref_allele || '_' || alt_allele
            as variant_key,
        variant_type,
        genotype,
        cast(read_depth as integer) as read_depth,
        cast(variant_allele_count as integer) as variant_allele_count,
        cast(variant_allele_freq as double) as variant_allele_freq,
        cast(quality as double) as quality,
        filter_status,
        load_id,
        ingested_at
    from source
)

select * from renamed

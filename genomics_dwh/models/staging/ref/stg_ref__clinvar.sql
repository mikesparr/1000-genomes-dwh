{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_ref__clinvar') }}
),

renamed as (
    select
        chromosome,
        cast(position as bigint) as position,
        ref_allele,
        alt_allele,
        chromosome || '_' || position || '_' || ref_allele || '_' || alt_allele as variant_key,
        rsid,
        clnsig as clinvar_significance,
        clndn as clinvar_disease_names,
        clnrevstat as clinvar_review_status,
        geneinfo,
        load_id,
        ingested_at
    from source
)

select * from renamed

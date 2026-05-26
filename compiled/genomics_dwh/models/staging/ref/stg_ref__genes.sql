

with source as (
    select * from read_parquet('../bronze/raw_ref__genes.parquet')
),

renamed as (
    select
        ensembl_id,
        gene_symbol,
        chromosome,
        cast(start_position as bigint) as gene_start,
        cast(end_position as bigint) as gene_end,
        strand,
        biotype,
        load_id,
        ingested_at
    from source
)

select * from renamed
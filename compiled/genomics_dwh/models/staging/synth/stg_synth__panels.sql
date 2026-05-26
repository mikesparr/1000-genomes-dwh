

with source as (
    select * from read_parquet('../bronze/raw_synth__panels.parquet')
),

renamed as (
    select
        panel_id,
        patient_id,
        cast(variant_index as integer) as variant_index,
        chromosome,
        cast(position as bigint) as position,
        ref_allele,
        alt_allele,
        variant_key,
        cast(simulated_tumor_vaf as double) as simulated_tumor_vaf,
        cast(panel_design_date as date) as panel_design_date,
        load_id,
        ingested_at
    from source
)

select * from renamed
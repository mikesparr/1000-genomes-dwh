
  




with variants as (
    select * from "ci_warehouse"."main"."stg_1kg__variants"
    
),

variant_dim as (
    select
        variant_sk,
        variant_key
    from "ci_warehouse"."main"."dim_variant"
),

patient_dim as (
    select
        patient_sk,
        sample_id_1kg
    from "ci_warehouse"."main"."dim_patient"
    where is_current
),

joined as (
    select
        
    md5(
      coalesce(cast(v.sample_id as varchar), '_NULL_') || '_' || coalesce(cast(v.variant_key as varchar), '_NULL_')
    )
 as observation_sk,
        v.sample_id as sample_id_1kg,
        p.patient_sk,
        d.variant_sk,
        v.variant_key,
        v.chromosome,
        v.position,
        v.ref_allele,
        v.alt_allele,
        v.variant_type,
        v.genotype,
        v.read_depth,
        v.variant_allele_count,
        v.variant_allele_freq,
        v.quality,
        v.filter_status,
        v.load_id,
        v.ingested_at
    from variants as v
    left join variant_dim as d on v.variant_key = d.variant_key
    left join patient_dim as p on v.sample_id = p.sample_id_1kg
)

select * from joined

    order by chromosome, position

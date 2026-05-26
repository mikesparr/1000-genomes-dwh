{{ apply_clustering(['chromosome', 'cast(position / 1000000 as integer)']) }}

{{ config(
    materialized='incremental',
    unique_key=['sample_id_1kg', 'variant_key'],
    on_schema_change='append_new_columns'
) }}

with variants as (
    select * from {{ ref('stg_1kg__variants') }}
    {% if is_incremental() %}
        -- Only pick up new load_ids since the last run
        where load_id not in (select distinct load_id from {{ this }})
    {% endif %}
),

variant_dim as (
    select
        variant_sk,
        variant_key
    from {{ ref('dim_variant') }}
),

patient_dim as (
    select
        patient_sk,
        sample_id_1kg
    from {{ ref('dim_patient') }}
    where is_current
),

joined as (
    select
        {{ make_surrogate_key(['v.sample_id', 'v.variant_key']) }} as observation_sk,
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
{% if target.type == 'duckdb' %}
    order by chromosome, position
{% endif %}

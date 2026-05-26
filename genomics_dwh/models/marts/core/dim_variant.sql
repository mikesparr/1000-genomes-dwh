{{ config(
    materialized='table',
    post_hook=[
      "create index if not exists idx_dim_variant_key on {{ this }} (variant_key)",
      "create index if not exists idx_dim_variant_rsid on {{ this }} (rsid)"
    ]
) }}

with annotated as (
    select * from {{ ref('int_variants__annotated') }}
),

-- int_variants__annotated has multiple rows per variant_key from two fan-out sources:
--   1. Genes overlap — one variant can sit inside multiple gene definitions
--   2. ClinVar has multiple submissions per variant — different labs, conflicting calls
-- The dimension is variant-scoped, not (variant × gene × clinvar)-scoped, so we collapse
-- to one row per variant_key here. If "all overlapping genes" is ever needed downstream,
-- build a bridge_variant_gene model — don't denormalize the dimension.
deduped as (
    select *
    from annotated
    qualify row_number() over (
        partition by variant_key
        order by
            -- Prefer rows with gene info filled in
            case when gene_symbol is not null then 0 else 1 end,
            -- Prefer rows with ClinVar info filled in
            case when clinvar_significance is not null then 0 else 1 end,
            -- Stable tiebreaks so re-runs are deterministic
            gene_symbol nulls last,
            clinvar_review_status nulls last
    ) = 1
)

select
    {{ make_surrogate_key(['variant_key']) }} as variant_sk,
    variant_key,
    chromosome,
    position,
    ref_allele,
    alt_allele,
    variant_type,
    gene_symbol,
    ensembl_id,
    biotype,
    rsid,
    clinvar_significance,
    clinvar_disease_names,
    clinvar_review_status
from deduped

{{ config(materialized='table') }}

with variants as (
    select
        variant_key,
        chromosome,
        position,
        ref_allele,
        alt_allele,
        variant_type
    from {{ ref('stg_1kg__variants') }}
    -- Distinct because the same variant appears across many samples in the variants
    -- table; for the gene/clinvar dimension we only care about the variant identity.
    group by 1, 2, 3, 4, 5, 6
),

genes as (
    select
        gene_symbol,
        ensembl_id,
        chromosome,
        gene_start,
        gene_end,
        biotype
    from {{ ref('stg_ref__genes') }}
),

clinvar as (
    select
        variant_key,
        rsid,
        clinvar_significance,
        clinvar_disease_names,
        clinvar_review_status
    from {{ ref('stg_ref__clinvar') }}
),

variant_to_gene as (
    select
        v.variant_key,
        v.chromosome,
        v.position,
        v.ref_allele,
        v.alt_allele,
        v.variant_type,
        g.gene_symbol,
        g.ensembl_id,
        g.biotype
    from variants as v
    left join genes as g
        on
            v.chromosome = g.chromosome
            and v.position between g.gene_start and g.gene_end
),

with_clinvar as (
    select
        vg.*,
        cv.rsid,
        cv.clinvar_significance,
        cv.clinvar_disease_names,
        cv.clinvar_review_status
    from variant_to_gene as vg
    left join clinvar as cv on vg.variant_key = cv.variant_key
)

select * from with_clinvar

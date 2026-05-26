-- analyses/q01_pathogenic_variants_in_genes_by_ancestry.sql
--
-- Persona: Genomic Researcher
-- Question: "Pull all pathogenic variants in <gene set> across <ancestry group> samples"
--
-- Demonstrates: star-schema joins (fact -> 3 dims), ClinVar significance filtering,
-- ancestry-stratified analysis. The kind of query that drives downstream papers and
-- IRB submissions.
--
-- For chr22 specifically, swap in chr22 cancer-relevant genes (NF2, CHEK2, EWSR1, BCR).
-- Generalizes to any gene set + any super-population.
--
-- Run: dbt show --select q01_pathogenic_variants_in_genes_by_ancestry --limit 25

with target_genes as (
    -- chr22 cancer-relevant gene set; expand via COSMIC Cancer Gene Census in production
    select unnest(['NF2', 'CHEK2', 'EWSR1', 'BCR', 'PDGFB', 'EP300', 'SMARCB1']) as gene_symbol
),

target_population as (
    select 'EUR' as super_population
)

select
    v.gene_symbol,
    v.variant_key,
    v.chromosome,
    v.position,
    v.ref_allele,
    v.alt_allele,
    v.rsid,
    v.clinvar_significance,
    v.clinvar_disease_names,
    pop.super_population,
    count(distinct fvo.sample_id_1kg) as n_samples_with_variant,
    avg(fvo.variant_allele_freq) as mean_vaf,
    avg(fvo.read_depth) as mean_read_depth
from {{ ref('fct_variant_observation') }} as fvo
inner join {{ ref('dim_variant') }} as v on fvo.variant_sk = v.variant_sk
inner join {{ ref('dim_patient') }} as p on fvo.patient_sk = p.patient_sk
inner join {{ ref('dim_population') }} as pop
    on
        p.ancestry_super_population = pop.super_population
        and p.ancestry_population_code = pop.population_code
where
    v.gene_symbol in (select gene_symbol from target_genes)
    and pop.super_population in (select super_population from target_population)
    and (
        v.clinvar_significance ilike '%pathogenic%'
        or v.clinvar_significance ilike '%likely_pathogenic%'
    )
    and p.is_current
group by
    v.gene_symbol,
    v.variant_key,
    v.chromosome,
    v.position,
    v.ref_allele,
    v.alt_allele,
    v.rsid,
    v.clinvar_significance,
    v.clinvar_disease_names,
    pop.super_population
order by n_samples_with_variant desc, v.gene_symbol asc, v.position asc

-- analyses/q02_allele_frequency_by_population.sql
--
-- Persona: Genomic Researcher
-- Question: "What's the allele frequency of variant X by super-population?"
--
-- Demonstrates: aggregation across populations, allele frequency calculation
-- from genotype data (not just AC/AN counts), and the kind of cross-population
-- comparison that's the bread-and-butter of population genetics.
--
-- Set the variant_key filter for the variant of interest. Run for any chr22 SNV
-- you can find in dim_variant.
--
-- Run: dbt show --select q02_allele_frequency_by_population --limit 10

with variant_of_interest as (
    -- Pick any variant_key that exists in dim_variant; substitute as needed
    select variant_key
    from "ci_warehouse"."main"."dim_variant"
    where
        variant_type = 'SNV'
        and rsid is not null
    order by variant_key
    limit 1
),

genotyped as (
    select
        fvo.variant_key,
        pop.super_population,
        fvo.sample_id_1kg,
        fvo.genotype,
        -- Count alt alleles per genotype: 0/0=0, 0/1=1, 1/1=2, ./.=null
        case
            when fvo.genotype in ('0/0', '0|0') then 0
            when fvo.genotype in ('0/1', '0|1', '1/0', '1|0') then 1
            when fvo.genotype in ('1/1', '1|1') then 2
        end as alt_allele_count,
        case
            when fvo.genotype in ('./.', '.|.') then 0
            else 2
        end as called_allele_count
    from "ci_warehouse"."main"."fct_variant_observation" as fvo
    inner join variant_of_interest as voi on fvo.variant_key = voi.variant_key
    inner join "ci_warehouse"."main"."dim_patient" as p
        on fvo.patient_sk = p.patient_sk
    inner join "ci_warehouse"."main"."dim_population" as pop
        on
            p.ancestry_super_population = pop.super_population
            and p.ancestry_population_code = pop.population_code
    where p.is_current
)

select
    variant_key,
    super_population,
    count(distinct sample_id_1kg) as n_samples,
    sum(alt_allele_count) as alt_allele_total,
    sum(called_allele_count) as called_allele_total,
    cast(sum(alt_allele_count) as double) / nullif(sum(called_allele_count), 0)
        as allele_frequency,
    sum(case when alt_allele_count = 2 then 1 else 0 end) as homozygous_alt_count,
    sum(case when alt_allele_count = 1 then 1 else 0 end) as heterozygous_count
from genotyped
where alt_allele_count is not null
group by variant_key, super_population
order by allele_frequency desc
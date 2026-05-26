

select distinct
    
    md5(
      coalesce(cast(ensembl_id as varchar), '_NULL_')
    )
 as gene_sk,
    ensembl_id,
    gene_symbol,
    chromosome,
    gene_start,
    gene_end,
    biotype,
    coalesce(gene_symbol in (
        -- Tiny seed list of cancer genes for chr22; expand using COSMIC Cancer Gene Census
        'NF2', 'CHEK2', 'EWSR1', 'BCR', 'PDGFB', 'EP300', 'SMARCB1'
    ), false) as is_cancer_gene
from "ci_warehouse"."main"."stg_ref__genes"
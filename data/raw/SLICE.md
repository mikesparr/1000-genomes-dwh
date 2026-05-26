# Project Data Slice

This document describes the deterministic slice of 1000 Genomes data used for local
development. The fetch scripts in  reproduce this slice exactly given the
same parameters.

## Active slice (laptop development)
- **Chromosome**: 22 (smallest autosome, ~50 Mb — ideal for local iteration)
- **Samples**: 50 (deterministic, seed=42; exact list in )
- **File types**: SNV gVCF + tabix index (, )
- **Source bucket**: 
- **Reference build**: hg38 (DRAGEN v3.5.7b reanalysis)

## Reference data
- 1KG sample panel TSV (population, sex, family relationships)
- GENCODE v44 basic annotation, filtered to chr22
- ClinVar GRCh38, filtered to chr22 (chromosome renamed  →  to match DRAGEN)

## Scale-up plan
- Phase 6: full chr22 + 2-3 more chromosomes for larger model testing
- Phase 7 (Snowflake): all 22 autosomes, all 3,202 samples, full DRAGEN v4.x outputs

## Reproducibility note
To regenerate this exact slice on a new machine:
  python loader/fetch_1kg_data.py --samples 50 --seed 42
  python loader/extract_region.py --region chr22
  bash loader/fetch_reference_data.sh

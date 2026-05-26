#!/usr/bin/env bash
# Fetch supporting reference data: 1KG sample panel, GENCODE annotation, ClinVar.
# Idempotent: re-running skips files that already exist.
# All filtered/transformed to chr22 to match the project's working slice.

set -euo pipefail

REF_DIR="data/raw/ref"
mkdir -p "$REF_DIR"
cd "$(git rev-parse --show-toplevel)"

# --- 1. 1KG sample panel (TSV: sample, pop, super_pop, sex, family) ---
PANEL="$REF_DIR/1kg_sample_panel.tsv"
if [[ ! -f "$PANEL" ]]; then
    echo "Fetching 1KG sample panel..."
    curl -fsSL -o "$PANEL" \
        https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/release/20130502/integrated_call_samples_v3.20130502.ALL.panel
    echo "  $(wc -l < "$PANEL") lines"
else
    echo "SKIP $PANEL (already present)"
fi

# --- 2. GENCODE basic annotation, chr22 only ---
GENCODE_FULL="$REF_DIR/gencode_v44.basic.gff3.gz"
GENCODE_CHR22="$REF_DIR/gencode_v44_chr22.gff3.gz"
if [[ ! -f "$GENCODE_CHR22" ]]; then
    if [[ ! -f "$GENCODE_FULL" ]]; then
        echo "Fetching GENCODE v44 basic annotation..."
        curl -fsSL -o "$GENCODE_FULL" \
            https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_44/gencode.v44.basic.annotation.gff3.gz
    fi
    echo "Filtering GENCODE to chr22..."
    gunzip -c "$GENCODE_FULL" | awk '$1 == "chr22" || $1 ~ /^#/' | gzip > "$GENCODE_CHR22"
    # Validate: chr22 should have ~80k lines. Anything tiny means awk silently failed.
    LINE_COUNT=$(gunzip -c "$GENCODE_CHR22" | wc -l | tr -d ' ')
    if [[ "$LINE_COUNT" -lt 1000 ]]; then
        echo "ERROR: GENCODE chr22 filter produced only $LINE_COUNT lines — expected ~80,000."
        echo "       Removing truncated output so re-running regenerates from scratch."
        rm -f "$GENCODE_CHR22"
        exit 1
    fi
    echo "  $(gunzip -c "$GENCODE_CHR22" | grep -cv '^#') annotation lines"
else
    echo "SKIP $GENCODE_CHR22 (already present)"
fi

# --- 3. ClinVar GRCh38, chr22 only ---
# Caveat: ClinVar uses '22' (no chr prefix); DRAGEN uses 'chr22' (with prefix).
# We rename '22' -> 'chr22' so downstream joins on chromosome name "just work".
CLINVAR_FULL="$REF_DIR/clinvar.vcf.gz"
CLINVAR_CHR22="$REF_DIR/clinvar_chr22.vcf.gz"
if [[ ! -f "$CLINVAR_CHR22" ]]; then
    if [[ ! -f "$CLINVAR_FULL" ]]; then
        echo "Fetching ClinVar GRCh38..."
        curl -fsSL -o "$CLINVAR_FULL" \
            https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh38/clinvar.vcf.gz
    fi
    echo "Filtering ClinVar to chr22 and renaming 22 -> chr22..."
    gunzip -c "$CLINVAR_FULL" | \
        awk 'BEGIN{OFS="\t"} /^#/ {print; next} $1 == "22" {$1="chr22"; print}' | \
        bgzip > "$CLINVAR_CHR22"
    # Validate: chr22 ClinVar should have tens of thousands of variants
    VARIANT_COUNT=$(bcftools view "$CLINVAR_CHR22" 2>/dev/null | grep -cv '^#' || echo 0)
    if [[ "$VARIANT_COUNT" -lt 1000 ]]; then
        echo "ERROR: ClinVar chr22 filter produced only $VARIANT_COUNT variants — expected ~95,000."
        echo "       Removing truncated output so re-running regenerates from scratch."
        rm -f "$CLINVAR_CHR22" "${CLINVAR_CHR22}.tbi"
        exit 1
    fi
    bcftools index -t "$CLINVAR_CHR22"
    echo "  $VARIANT_COUNT variants"
else
    echo "SKIP $CLINVAR_CHR22 (already present)"
fi

echo ""
echo "Reference data ready in $REF_DIR/"
ls -lh "$REF_DIR/"

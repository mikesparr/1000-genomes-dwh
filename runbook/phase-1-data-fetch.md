# Phase 1 - Data Acquisition
**Goal:** pull a chromosome-22 slice of 1000 Genomes DRAGEN data + supporting reference data into a deterministic, repeatable, idempotent local snapshot. The Python scripts produced here are the seed of every Bronze loader you'll ever write.

## Commands (step-by-step)
```bash
#######################################################
# 1. DATA ACQUISITION
# - Idempotent (re-running skips files already present; safe to retry after failures; no wasted bandwidth)
# - Deterministic (Same seed -> same set of samples; reproducibility; you can compare runs over time)
# - Manifested (every action logged with timestamp, size, source URL; ops.load_audit precursor)
# - Parallel (many files downloaded concurrently; speed up file downloads)
# - Configurable (sample count, file types, region passed as CLI args; different slices for scale-up phases)
# - Resumable (interruption leaves valid state; laptop closed mid-run? no problem)
#
# STEPS
# - Fetch dependencies
# - load data
# - extract chr22 region (laptop work)
# - fetch supporting reference data (1KG sample panel, GENCODE annotation, ClinVar)
#######################################################

# install fetch dependencies (assume venv activated and in project root dir)
# if not: source .venv/bin/activate

# boto3: idiomatic Python S3 client
pip install boto3

# bcftools: fast genomic file subsetting
brew install bcftools

# Verify boto
python -c "import boto3; print(f'boto3 {boto3.__version__}')"
# boto3 1.43.14

# Verify bcftools
bcftools --version | head -1
# bcftools 1.23.1

# Pin
pip freeze > requirements.txt
git add requirements.txt
git commit -m "Add boto3 for S3 fetch script"

# create data dir and add reference doc to remember what we're using
mkdir -p data/raw
cat > data/raw/SLICE.md <<'EOF'
# Project Data Slice

This document describes the deterministic slice of 1000 Genomes data used for local
development. The fetch scripts in `loader/` reproduce this slice exactly given the
same parameters.

## Active slice (laptop development)
- **Chromosome**: 22 (smallest autosome, ~50 Mb — ideal for local iteration)
- **Samples**: 50 (deterministic, seed=42; exact list in `1kg/manifest.json`)
- **File types**: SNV gVCF + tabix index (`*.hard-filtered.gvcf.gz`, `*.gvcf.gz.tbi`)
- **Source bucket**: `s3://1000genomes-dragen/data/dragen-3.5.7b/hg38_altaware_nohla-cnv-anchored/`
- **Reference build**: hg38 (DRAGEN v3.5.7b reanalysis)

## Reference data
- 1KG sample panel TSV (population, sex, family relationships)
- GENCODE v44 basic annotation, filtered to chr22
- ClinVar GRCh38, filtered to chr22 (chromosome renamed `22` → `chr22` to match DRAGEN)

## Scale-up plan
- Phase 6: full chr22 + 2-3 more chromosomes for larger model testing
- Phase 7 (Snowflake): all 22 autosomes, all 3,202 samples, full DRAGEN v4.x outputs

## Reproducibility note
To regenerate this exact slice on a new machine:
  python loader/fetch_1kg_data.py --samples 50 --seed 42
  python loader/extract_region.py --region chr22
  bash loader/fetch_reference_data.sh
EOF

# init python fetch script loader dir
mkdir -p loader
touch loader/__init__.py

# create loader/fetch_1kg_data.py
cat > loader/fetch_1kg_data.py <<'EOF'
#!/usr/bin/env python3
"""
Fetch a deterministic slice of 1000 Genomes DRAGEN reanalysis data from S3.

Idempotent: skips files already present locally.
Logged: writes manifest.json with what was fetched (sizes, source URIs, timestamps).
Parallel: downloads multiple files concurrently via ThreadPoolExecutor.
Deterministic: same --seed produces same sample set.

Usage:
  python loader/fetch_1kg_data.py --samples 50 --seed 42 --workers 8
"""

import argparse
import fnmatch
import json
import logging
import random
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore import UNSIGNED
from botocore.config import Config

BUCKET = "1000genomes-dragen"
PREFIX = "data/dragen-3.5.7b/hg38_altaware_nohla-cnv-anchored"
DEFAULT_PATTERNS = ["*.hard-filtered.gvcf.gz", "*.hard-filtered.gvcf.gz.tbi"]


def list_sample_ids(s3, n: int, seed: int) -> list[str]:
    """Return a deterministic subset of n sample IDs from the bucket."""
    paginator = s3.get_paginator("list_objects_v2")
    samples = set()
    for page in paginator.paginate(Bucket=BUCKET, Prefix=f"{PREFIX}/", Delimiter="/"):
        for cp in page.get("CommonPrefixes", []):
            sample_id = cp["Prefix"].rstrip("/").split("/")[-1]
            if sample_id.startswith(("HG", "NA")):
                samples.add(sample_id)
    samples = sorted(samples)
    rng = random.Random(seed)
    rng.shuffle(samples)
    return samples[:n]


def list_sample_files(s3, sample_id: str, patterns: list[str]) -> list[str]:
    """List S3 keys for one sample matching any of the given glob patterns."""
    prefix = f"{PREFIX}/{sample_id}/"
    response = s3.list_objects_v2(Bucket=BUCKET, Prefix=prefix)
    matched = []
    for obj in response.get("Contents", []):
        key = obj["Key"]
        filename = key.rsplit("/", 1)[-1]
        if any(fnmatch.fnmatch(filename, p) for p in patterns):
            matched.append(key)
    return matched


def fetch_sample(s3, sample_id: str, dest_dir: Path, patterns: list[str]) -> dict:
    """Fetch all files matching patterns for one sample. Idempotent."""
    sample_dir = dest_dir / sample_id
    sample_dir.mkdir(parents=True, exist_ok=True)

    keys = list_sample_files(s3, sample_id, patterns)
    if not keys:
        logging.warning(f"{sample_id}: no files matched {patterns}")
        return {"sample_id": sample_id, "files": []}

    fetched = []
    for key in keys:
        filename = key.rsplit("/", 1)[-1]
        local_path = sample_dir / filename
        s3_uri = f"s3://{BUCKET}/{key}"

        if local_path.exists():
            fetched.append({
                "file": filename,
                "status": "skipped",
                "size_bytes": local_path.stat().st_size,
                "source_uri": s3_uri,
            })
            continue

        try:
            s3.download_file(BUCKET, key, str(local_path))
            size = local_path.stat().st_size
            logging.info(f"  {sample_id}/{filename} ({size:,} bytes)")
            fetched.append({
                "file": filename,
                "status": "fetched",
                "size_bytes": size,
                "source_uri": s3_uri,
            })
        except Exception as e:
            logging.error(f"  FAILED {sample_id}/{filename}: {e}")
            fetched.append({
                "file": filename,
                "status": "failed",
                "error": str(e),
                "source_uri": s3_uri,
            })

    return {"sample_id": sample_id, "files": fetched}


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--samples", type=int, default=50)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--dest", type=Path, default=Path("data/raw/1kg"))
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--patterns", nargs="+", default=DEFAULT_PATTERNS,
                        help="Glob patterns to match per sample")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    s3 = boto3.client("s3", config=Config(signature_version=UNSIGNED))

    logging.info(f"Listing samples from s3://{BUCKET}/{PREFIX}/")
    sample_ids = list_sample_ids(s3, args.samples, args.seed)
    logging.info(f"Selected {len(sample_ids)} samples (seed={args.seed})")
    logging.info(f"  First 5: {sample_ids[:5]}")

    args.dest.mkdir(parents=True, exist_ok=True)
    started_at = datetime.now(timezone.utc).isoformat()

    samples_manifest = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {
            ex.submit(fetch_sample, s3, sid, args.dest, args.patterns): sid
            for sid in sample_ids
        }
        for fut in as_completed(futures):
            samples_manifest.append(fut.result())

    finished_at = datetime.now(timezone.utc).isoformat()

    manifest = {
        "started_at": started_at,
        "finished_at": finished_at,
        "bucket": BUCKET,
        "prefix": PREFIX,
        "samples_requested": args.samples,
        "samples_fetched": len(samples_manifest),
        "seed": args.seed,
        "patterns": args.patterns,
        "samples": sorted(samples_manifest, key=lambda s: s["sample_id"]),
    }

    manifest_path = args.dest / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))

    total_size = sum(
        f.get("size_bytes", 0)
        for s in samples_manifest
        for f in s["files"]
    )
    failed = sum(
        1
        for s in samples_manifest
        for f in s["files"]
        if f.get("status") == "failed"
    )

    logging.info(f"Manifest: {manifest_path}")
    logging.info(f"Total size on disk: {total_size / 1e9:.2f} GB")
    if failed:
        logging.error(f"{failed} files failed to download — check manifest")
        sys.exit(1)


if __name__ == "__main__":
    main()
EOF

# run the fetch (100-200GB disk; --samples 25 or 10 if constrained; takes 30-45 min)
python loader/fetch_1kg_data.py --samples 50 --seed 42 --workers 8
# 19:58:57 [INFO] Listing samples from s3://1000genomes-dragen/data/dragen-3.5.7b/hg38_altaware_nohla-cnv-anchored/
# 19:58:58 [INFO] Selected 50 samples (seed=42)
# 19:58:58 [INFO]   First 5: ['HG02490', 'HG01618', 'HG02807', 'NA20798', 'HG03833']
# 20:04:58 [INFO]   HG02807/HG02807.hard-filtered.gvcf.gz (2,771,178,968 bytes)
# 20:05:00 [INFO]   HG02807/HG02807.hard-filtered.gvcf.gz.tbi (1,279,142 bytes)
# 20:06:04 [INFO]   HG02490/HG02490.hard-filtered.gvcf.gz (3,377,248,699 bytes)
# 20:06:06 [INFO]   HG02490/HG02490.hard-filtered.gvcf.gz.tbi (1,297,056 bytes)
# ...
# 20:48:23 [INFO]   HG00100/HG00100.hard-filtered.gvcf.gz (4,442,494,453 bytes)
# 20:48:23 [INFO]   HG00100/HG00100.hard-filtered.gvcf.gz.tbi (1,352,727 bytes)
# 20:48:23 [INFO] Manifest: data/raw/1kg/manifest.json
# 20:48:23 [INFO] Total size on disk: 195.36 GB

# Sample count
jq '.samples | length' data/raw/1kg/manifest.json
# 50

# How many files per sample (should be 2: gvcf.gz + tbi)
jq '.samples[] | {sample_id, file_count: (.files | length)}' data/raw/1kg/manifest.json | head -20

# Anything fail?
jq '.samples[] | .files[] | select(.status == "failed")' data/raw/1kg/manifest.json

# create loader/extract_region.py  (extract chr22 region for laptop work)
cat > loader/extract_region.py <<'EOF'
#!/usr/bin/env python3
"""
Extract a single chromosome (or region) from each downloaded gVCF using bcftools.

Idempotent: skips files already extracted.
Parallel: processes multiple samples concurrently.
Logged: writes extraction_manifest.json.

Usage:
  python loader/extract_region.py --region chr22 --workers 4
"""

import argparse
import json
import logging
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def extract_one(input_path: Path, output_path: Path, region: str) -> dict:
    sample = input_path.parent.name
    if output_path.exists():
        return {
            "sample": sample,
            "status": "skipped",
            "output": str(output_path),
            "size_bytes": output_path.stat().st_size,
        }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["bcftools", "view", "-r", region, str(input_path),
             "-O", "z", "-o", str(output_path)],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["bcftools", "index", "-t", str(output_path)],
            check=True, capture_output=True,
        )
        return {
            "sample": sample,
            "status": "extracted",
            "output": str(output_path),
            "size_bytes": output_path.stat().st_size,
        }
    except subprocess.CalledProcessError as e:
        return {
            "sample": sample,
            "status": "failed",
            "output": str(output_path),
            "error": (e.stderr or b"").decode(errors="replace"),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", default="chr22",
                        help="Region to extract (e.g., chr22, chr22:17000000-18000000)")
    parser.add_argument("--input-dir", type=Path, default=Path("data/raw/1kg"))
    parser.add_argument("--output-dir", type=Path, default=Path("data/raw/1kg_chr22"))
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    gvcfs = sorted(args.input_dir.glob("*/*.hard-filtered.gvcf.gz"))
    logging.info(f"Found {len(gvcfs)} gVCFs to process")

    region_safe = args.region.replace(":", "_").replace("-", "_")
    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {}
        for gvcf in gvcfs:
            sample = gvcf.parent.name
            output = args.output_dir / sample / f"{sample}.{region_safe}.vcf.gz"
            futures[ex.submit(extract_one, gvcf, output, args.region)] = sample

        for fut in as_completed(futures):
            r = fut.result()
            if r["status"] == "extracted":
                logging.info(f"  {r['sample']}: {r['size_bytes']:,} bytes")
            elif r["status"] == "failed":
                logging.error(f"  {r['sample']}: {r.get('error', 'unknown')[:200]}")
            results.append(r)

    manifest = {
        "region": args.region,
        "input_dir": str(args.input_dir),
        "output_dir": str(args.output_dir),
        "results": sorted(results, key=lambda r: r["sample"]),
    }
    manifest_path = args.output_dir / "extraction_manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2))

    ok = sum(1 for r in results if r["status"] in ("extracted", "skipped"))
    failed = sum(1 for r in results if r["status"] == "failed")
    logging.info(f"Done: {ok} ok, {failed} failed")
    logging.info(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()
EOF

# run it
python loader/extract_region.py --region chr22 --workers 4
# 20:50:32 [INFO] Found 50 gVCFs to process
# 20:50:37 [INFO]   HG00096: 48,453,001 bytes
# 20:50:37 [INFO]   HG00285: 48,819,784 bytes
# ...
# 20:51:42 [INFO]   NA20851: 59,597,046 bytes
# 20:51:42 [INFO] Done: 50 ok, 0 failed
# 20:51:42 [INFO] Manifest: data/raw/1kg_chr22/extraction_manifest.json

# Confirm size shrunk dramatically
du -sh data/raw/1kg              # whole-genome gVCFs - should be ~182GB total
du -sh data/raw/1kg_chr22        # chr22-only — should be ~2.6GB total

# create loader/fetch_reference_data.sh
# - 1kg sample panel (population/sex/family metadata)
# - GENCODE annotation (gene coordinates)
# - ClinVar (known variant significance)
cat > loader/fetch_reference_data.sh <<'EOF'
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
EOF

# make it executable
chmod +x loader/fetch_reference_data.sh

# run it
./loader/fetch_reference_data.sh
# Fetching 1KG sample panel...
#       2505 lines
# Fetching GENCODE v44 basic annotation...
# Filtering GENCODE to chr22...
#   42308 annotation lines
# Fetching ClinVar GRCh38...
# Filtering ClinVar to chr22 and renaming 22 -> chr22...
#   96090 variants

# Reference data ready in data/raw/ref/

# Sanity check: a chr22 extract should have only chr22 records
bcftools view data/raw/1kg_chr22/HG00096/HG00096.chr22.vcf.gz | grep -v '^#' | awk '{print $1}' | sort -u
# Expected output: just "chr22"

# Sanity check: ClinVar should also be chr22-only after renaming
bcftools view data/raw/ref/clinvar_chr22.vcf.gz | grep -v '^#' | head -3 | awk '{print $1}'
# Expected: "chr22" (not "22")

# commit progress
git add loader/ data/raw/SLICE.md
git commit -m "Phase 1: data acquisition scripts (fetch, extract, reference)"
```
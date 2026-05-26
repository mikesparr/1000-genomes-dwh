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

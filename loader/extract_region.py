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

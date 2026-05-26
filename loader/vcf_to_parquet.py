#!/usr/bin/env python3
"""
Convert chr22 VCFs from Phase 1 into Parquet files for the Bronze layer.

Idempotent: skip Parquet files already present (unless --force).
Manifested: writes manifest.json with rows-per-sample.
Audited: inserts a row into ops.load_audit per run.

Splits multi-allelic rows. Filters gVCF <NON_REF> blocks. Fills in audit columns
(load_id, source_uri, ingested_at).

Usage:
  python loader/vcf_to_parquet.py
  python loader/vcf_to_parquet.py --force
  python loader/vcf_to_parquet.py --input-dir data/raw/1kg_chr22 --bronze-dir bronze
"""

import argparse
import json
import logging
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq
from cyvcf2 import VCF


def classify_variant(ref: str, alt: str) -> str:
    """Classify a biallelic variant by the lengths of REF and ALT."""
    if alt == "*" or alt.startswith("<"):
        return "OTHER"  # spanning deletion or symbolic allele
    if len(ref) == 1 and len(alt) == 1:
        return "SNV"
    if len(ref) < len(alt):
        return "INSERTION"
    if len(ref) > len(alt):
        return "DELETION"
    return "MNP"  # multi-nucleotide polymorphism (same length, different sequence)


def vcf_record_to_rows(record, sample_id: str, load_id: str,
                       source_uri: str, ingested_at: datetime) -> list[dict]:
    """
    Convert one cyvcf2 record to one or more biallelic rows.

    Multi-allelic VCF records (REF=A, ALT=T,C) become multiple rows.
    gVCF <NON_REF> blocks return [] (filtered out).
    """
    # gVCF non-variant blocks: ALT is just <NON_REF>, no actual variant
    if all(a == "<NON_REF>" for a in record.ALT):
        return []

    rows = []
    # cyvcf2 exposes per-allele arrays; iterate over REAL alts only
    for alt_idx, alt in enumerate(record.ALT):
        if alt == "<NON_REF>":
            continue  # skip the gVCF reference-block sentinel

        # Genotype encoding: cyvcf2 returns [allele1, allele2, phased_bool]
        # We're single-sample so genotypes[0] is the only entry.
        gt_raw = record.genotypes[0] if record.genotypes else None
        if gt_raw is None:
            genotype = "./."
        else:
            sep = "|" if gt_raw[2] else "/"
            a1 = "." if gt_raw[0] < 0 else str(gt_raw[0])
            a2 = "." if gt_raw[1] < 0 else str(gt_raw[1])
            genotype = f"{a1}{sep}{a2}"

        # Allele depths: AD is per-allele (REF, ALT1, ALT2, ...). Index 0 = REF.
        depth = int(record.format("DP")[0][0]) if record.format("DP") is not None else None
        ad_array = record.format("AD")
        if ad_array is not None and ad_array.shape[1] > alt_idx + 1:
            ad_alt = int(ad_array[0][alt_idx + 1])
        else:
            ad_alt = None

        vaf = (ad_alt / depth) if (depth and ad_alt is not None and depth > 0) else None

        rows.append({
            "chromosome": record.CHROM,
            "position": int(record.POS),
            "ref_allele": record.REF,
            "alt_allele": alt,
            "variant_type": classify_variant(record.REF, alt),
            "sample_id": sample_id,
            "genotype": genotype,
            "read_depth": depth,
            "variant_allele_count": ad_alt,
            "variant_allele_freq": vaf,
            "quality": float(record.QUAL) if record.QUAL is not None else None,
            "filter_status": record.FILTER if record.FILTER else "PASS",
            "load_id": load_id,
            "source_uri": source_uri,
            "ingested_at": ingested_at,
        })
    return rows


# Schema defined explicitly so Parquet files are type-stable across runs.
PARQUET_SCHEMA = pa.schema([
    pa.field("chromosome", pa.string()),
    pa.field("position", pa.int64()),
    pa.field("ref_allele", pa.string()),
    pa.field("alt_allele", pa.string()),
    pa.field("variant_type", pa.string()),
    pa.field("sample_id", pa.string()),
    pa.field("genotype", pa.string()),
    pa.field("read_depth", pa.int32()),
    pa.field("variant_allele_count", pa.int32()),
    pa.field("variant_allele_freq", pa.float64()),
    pa.field("quality", pa.float64()),
    pa.field("filter_status", pa.string()),
    pa.field("load_id", pa.string()),
    pa.field("source_uri", pa.string()),
    pa.field("ingested_at", pa.timestamp("us", tz="UTC")),
])


def convert_one_vcf(vcf_path: Path, output_path: Path, load_id: str,
                    batch_size: int = 50_000) -> dict:
    """Stream one VCF to Parquet. Returns stats dict."""
    sample_id = vcf_path.stem.split(".")[0]  # HG00096.chr22.vcf -> HG00096
    source_uri = str(vcf_path.resolve())
    ingested_at = datetime.now(timezone.utc)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    vcf = VCF(str(vcf_path))
    writer = pq.ParquetWriter(str(output_path), PARQUET_SCHEMA, compression="zstd")

    rows_written = 0
    rows_failed = 0
    batch = []

    try:
        for record in vcf:
            try:
                rows = vcf_record_to_rows(record, sample_id, load_id, source_uri, ingested_at)
                batch.extend(rows)
                if len(batch) >= batch_size:
                    table = pa.Table.from_pylist(batch, schema=PARQUET_SCHEMA)
                    writer.write_table(table)
                    rows_written += len(batch)
                    batch = []
            except Exception as e:
                rows_failed += 1
                if rows_failed <= 5:
                    logging.warning(f"  {sample_id}: failed record at {record.CHROM}:{record.POS}: {e}")

        if batch:
            table = pa.Table.from_pylist(batch, schema=PARQUET_SCHEMA)
            writer.write_table(table)
            rows_written += len(batch)
    finally:
        writer.close()
        vcf.close()

    return {
        "sample_id": sample_id,
        "source_uri": source_uri,
        "output_path": str(output_path),
        "rows_written": rows_written,
        "rows_failed": rows_failed,
        "size_bytes": output_path.stat().st_size,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input-dir", type=Path, default=Path("data/raw/1kg_chr22"))
    parser.add_argument("--bronze-dir", type=Path, default=Path("bronze/raw_1kg__variants"))
    parser.add_argument("--warehouse", type=Path, default=Path("warehouse.duckdb"))
    parser.add_argument("--force", action="store_true", help="Re-convert files even if Parquet exists")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s [%(levelname)s] %(message)s",
                        datefmt="%H:%M:%S")

    vcfs = sorted(args.input_dir.glob("*/*.vcf.gz"))
    if not vcfs:
        logging.error(f"No VCFs found under {args.input_dir}/*/*.vcf.gz")
        sys.exit(1)

    args.bronze_dir.mkdir(parents=True, exist_ok=True)

    # Audit row: start
    load_id = str(uuid.uuid4())
    started_at = datetime.now(timezone.utc)
    con = duckdb.connect(str(args.warehouse))
    con.execute("""
        INSERT INTO ops.load_audit (load_id, source_table, source_uri, started_at, status)
        VALUES (?, 'raw_1kg__variants', ?, ?, 'running')
    """, [load_id, str(args.input_dir), started_at])
    con.close()

    logging.info(f"load_id = {load_id}")
    logging.info(f"Found {len(vcfs)} VCFs to convert")

    results = []
    total_rows = 0
    total_failed = 0
    for vcf_path in vcfs:
        sample_id = vcf_path.stem.split(".")[0]
        output_path = args.bronze_dir / f"sample={sample_id}" / "data.parquet"

        if output_path.exists() and not args.force:
            logging.info(f"SKIP {sample_id} (Parquet already present; use --force to overwrite)")
            continue

        stats = convert_one_vcf(vcf_path, output_path, load_id)
        logging.info(f"  {stats['sample_id']}: {stats['rows_written']:,} rows "
                     f"({stats['rows_failed']} failed)")
        results.append(stats)
        total_rows += stats["rows_written"]
        total_failed += stats["rows_failed"]

    finished_at = datetime.now(timezone.utc)
    elapsed = (finished_at - started_at).total_seconds()
    status = "success" if total_failed == 0 else "success_with_errors"

    # Audit row: finalize
    con = duckdb.connect(str(args.warehouse))
    con.execute("""
        UPDATE ops.load_audit
        SET finished_at = ?, status = ?, rows_loaded = ?, rows_failed = ?
        WHERE load_id = ?
    """, [finished_at, status, total_rows, total_failed, load_id])
    con.close()

    # Manifest
    manifest = {
        "load_id": load_id,
        "started_at": started_at.isoformat(),
        "finished_at": finished_at.isoformat(),
        "elapsed_seconds": elapsed,
        "status": status,
        "total_rows_written": total_rows,
        "total_rows_failed": total_failed,
        "samples": sorted(results, key=lambda r: r["sample_id"]),
    }
    manifest_path = args.bronze_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, default=str))

    logging.info(f"Wrote {total_rows:,} rows across {len(results)} samples in {elapsed:.1f}s")
    logging.info(f"Manifest: {manifest_path}")


if __name__ == "__main__":
    main()

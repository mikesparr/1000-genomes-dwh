#!/usr/bin/env python3
"""
Convert reference data (GENCODE GFF, ClinVar VCF) into Bronze Parquet.

GENCODE → bronze/raw_ref__genes.parquet (one row per gene, chr22 only)
ClinVar → bronze/raw_ref__clinvar.parquet (one row per variant, chr22 only)
"""

import argparse
import gzip
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path

import duckdb
import pandas as pd
from cyvcf2 import VCF


def parse_gencode(gff_path: Path) -> pd.DataFrame:
    """Extract gene-level rows from a GENCODE GFF3."""
    rows = []
    with gzip.open(gff_path, "rt") as f:
        for line in f:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 9 or fields[2] != "gene":
                continue
            chrom, _, feature, start, end, _, strand, _, attrs = fields
            attr_dict = {}
            for kv in attrs.split(";"):
                kv = kv.strip()
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    attr_dict[k] = v
            rows.append({
                "chromosome": chrom,
                "start_position": int(start),
                "end_position": int(end),
                "strand": strand,
                "ensembl_id": attr_dict.get("gene_id", "").split(".")[0],
                "gene_symbol": attr_dict.get("gene_name", ""),
                "biotype": attr_dict.get("gene_type", ""),
            })
    return pd.DataFrame(rows)


def parse_clinvar(vcf_path: Path) -> pd.DataFrame:
    """Extract clinical-significance rows from a ClinVar VCF."""
    rows = []
    vcf = VCF(str(vcf_path))
    for rec in vcf:
        info = dict(rec.INFO)
        for alt in rec.ALT:
            rows.append({
                "chromosome": rec.CHROM,
                "position": int(rec.POS),
                "ref_allele": rec.REF,
                "alt_allele": alt,
                "rsid": rec.ID if rec.ID else None,
                "clnsig": info.get("CLNSIG", ""),
                "clndn": info.get("CLNDN", ""),
                "clnrevstat": info.get("CLNREVSTAT", ""),
                "geneinfo": info.get("GENEINFO", ""),
            })
    vcf.close()
    return pd.DataFrame(rows)


def write_with_audit(df: pd.DataFrame, output_path: Path, source_table: str,
                     source_uri: str, warehouse_path: Path):
    load_id = str(uuid.uuid4())
    started_at = datetime.now(timezone.utc)

    con = duckdb.connect(str(warehouse_path))
    con.execute("""
        INSERT INTO ops.load_audit (load_id, source_table, source_uri, started_at, status)
        VALUES (?, ?, ?, ?, 'running')
    """, [load_id, source_table, source_uri, started_at])
    con.close()

    df["load_id"] = load_id
    df["source_uri"] = source_uri
    df["ingested_at"] = started_at

    output_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(output_path, compression="zstd", index=False)

    finished_at = datetime.now(timezone.utc)
    con = duckdb.connect(str(warehouse_path))
    con.execute("""
        UPDATE ops.load_audit
        SET finished_at = ?, status = 'success', rows_loaded = ?
        WHERE load_id = ?
    """, [finished_at, len(df), load_id])
    con.close()

    logging.info(f"Wrote {len(df):,} rows to {output_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gencode", type=Path, default=Path("data/raw/ref/gencode_v44_chr22.gff3.gz"))
    parser.add_argument("--clinvar", type=Path, default=Path("data/raw/ref/clinvar_chr22.vcf.gz"))
    parser.add_argument("--bronze-dir", type=Path, default=Path("bronze"))
    parser.add_argument("--warehouse", type=Path, default=Path("warehouse.duckdb"))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    logging.info(f"Parsing GENCODE: {args.gencode}")
    genes_df = parse_gencode(args.gencode)
    write_with_audit(genes_df, args.bronze_dir / "raw_ref__genes.parquet",
                     "raw_ref__genes", str(args.gencode.resolve()), args.warehouse)

    logging.info(f"Parsing ClinVar: {args.clinvar}")
    clinvar_df = parse_clinvar(args.clinvar)
    write_with_audit(clinvar_df, args.bronze_dir / "raw_ref__clinvar.parquet",
                     "raw_ref__clinvar", str(args.clinvar.resolve()), args.warehouse)


if __name__ == "__main__":
    main()

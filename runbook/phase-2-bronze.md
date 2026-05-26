# Phase 2 - Bronze Loader
**Goal:** Convert the chr22 VCFs from Phase 1 into Parquet (with audit columns), expose them as a DuckDB schema, and capture every load in an audit table. The Parquet files become the lakehouse Bronze layer; the DuckDB views are how dbt consumes them in Phase 4.

## Commands (step-by-step)
```bash
#######################################################
# 2. BRONZE LOADER
# - Convert chr22 VCFs from phase 1 to Parquet (with audit columns), expose as DuckDB
#   schema, and capture every load in an audit table. Parquet files become lakehouse Bronze 
#   layer; the DuckDB views are how dbt consumes them in phase 4
#
# DESIGN DECISIONS
# - every VCF record gets flattened into one row per 
#   (sample, chromosome, position, ref_allele, alt_allele) tuple. Two non-obvious 
#   choices baked into this shape:
# - multi-allelic splitting: single VCF row can encode multiple alternate alleles 
#   ( REF=A, ALT=T,C iw one row representing two variants ). Most analytic tools choke on this;
#   The standard fix is to "split" them into separate biallelic rows ( A->T and A->C ). 
#   We do this at ingestion so downstream models never have to.
# - gVCF non-variant blocks: gVCFs includ `<NON_REF>` records that represent stretches of 
#   homozygous-reference sequence (positions that match the reference, expressed as ranges 
#   to save space). For our use case - variant analysis - these blocks are noise. We filter 
#   them out at ingestion. (For coverage analysis they'd be essential, so don't reflexively
#   drop them in your real pipeline.)
#######################################################

# create loader/init_warehouse.sql - idempotent SQL that sets up the schemas and audit table
cat > loader/init_warehouse.sql <<'EOF'
-- loader/init_warehouse.sql
-- Idempotent warehouse initialization. Safe to re-run.

create schema if not exists bronze;
create schema if not exists ops;

create table if not exists ops.load_audit (
    load_id varchar primary key,
    source_table varchar not null,    -- e.g. 'raw_1kg__variants'
    source_uri varchar,               -- file or S3 URI
    started_at timestamp not null,
    finished_at timestamp,
    status varchar not null,          -- 'running', 'success', 'failed'
    rows_loaded bigint,
    rows_failed bigint,
    error_message varchar
);

create index if not exists idx_load_audit_table on ops.load_audit (source_table);
create index if not exists idx_load_audit_status on ops.load_audit (status);
EOF

# run it once
duckdb warehouse.duckdb < loader/init_warehouse.sql

# Verify
duckdb warehouse.duckdb -c "SHOW TABLES FROM ops; SHOW TABLES FROM bronze;"
# ┌────────────┐
# │    name    │
# │  varchar   │
# ├────────────┤
# │ load_audit │
# └────────────┘
# ┌─────────┐
# │  name   │
# │ varchar │
# └─────────┘
#   0 rows 

# create loader/vcf_to_parquet.py
cat > loader/vcf_to_parquet.py <<'EOF'
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
EOF

# run it (expect 3-5 min to run)
python loader/vcf_to_parquet.py
# 21:19:28 [INFO] load_id = d20fd4a4-23cb-4f8b-957f-ba30bdbf8d32
# 21:19:28 [INFO] Found 50 VCFs to convert
# 21:19:33 [INFO]   HG00096: 87,956 rows (0 failed)
# 21:19:39 [INFO]   HG00100: 89,975 rows (0 failed)
# ...
# 21:24:09 [INFO]   NA21133: 91,371 rows (0 failed)
# 21:24:09 [INFO] Wrote 4,744,579 rows across 50 samples in 287.4s
# 21:24:09 [INFO] Manifest: bronze/raw_1kg__variants/manifest.json


# Audit log
duckdb warehouse.duckdb -c "
  SELECT load_id, source_table, status, rows_loaded, rows_failed,
         (epoch(finished_at) - epoch(started_at)) AS elapsed_s
  FROM ops.load_audit
  ORDER BY started_at DESC
"

# Sanity check: read the Parquet directly
duckdb warehouse.duckdb -c "
  SELECT chromosome, count(*) AS rows, count(DISTINCT sample_id) AS samples
  FROM read_parquet('bronze/raw_1kg__variants/**/*.parquet', hive_partitioning=true)
  GROUP BY chromosome
"

# OPTIONAL IDEMPOTENCY CHECKS (RESILIENCY DRILL)

# 1. Re-run with no flags — every sample should be skipped
python loader/vcf_to_parquet.py
# Expected: "SKIP HG00096 (Parquet already present...)" 50 times, finishes in seconds.

# 2. Force re-conversion — every sample re-runs, audit gets a NEW load_id
python loader/vcf_to_parquet.py --force
# Expected: full re-run, but check ops.load_audit shows two rows now

duckdb warehouse.duckdb -c "SELECT load_id, started_at, rows_loaded FROM ops.load_audit ORDER BY started_at"
# ┌──────────────────────────────────────┬────────────────────────────┬─────────────┐
# │               load_id                │         started_at         │ rows_loaded │
# │               varchar                │         timestamp          │    int64    │
# ├──────────────────────────────────────┼────────────────────────────┼─────────────┤
# │ d20fd4a4-23cb-4f8b-957f-ba30bdbf8d32 │ 2026-05-25 21:19:21.655335 │     4744579 │
# │ 9fe25f5b-4210-47f7-b5e2-0cbf8560388c │ 2026-05-25 21:29:16.8533   │           0 │
# │ 25d9c301-0840-42ab-b927-ef807b37625b │ 2026-05-25 21:29:34.953186 │     4744579 │
# └──────────────────────────────────────┴────────────────────────────┴─────────────┘

# 3. Kill mid-run, then re-run
# Start with --force, kill with Ctrl-C after a few samples, then re-run without --force.
# Verify: the killed run has status='running' (orphaned) in load_audit, the re-run skips
# completed Parquet files and creates a new load_id. Done correctly, no data is lost or duplicated.

# create loader/panel_to_parquet.py  (load 1kg sample panel population/sex/family metadata)
cat > loader/panel_to_parquet.py <<'EOF'
#!/usr/bin/env python3
"""
Convert the 1000 Genomes sample panel TSV into a Bronze Parquet file.

Source: data/raw/ref/1kg_sample_panel.tsv (downloaded in Phase 1.6)
Output: bronze/raw_1kg__samples.parquet
"""

import argparse
import json
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path

import duckdb
import pandas as pd


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("data/raw/ref/1kg_sample_panel.tsv"))
    parser.add_argument("--output", type=Path, default=Path("bronze/raw_1kg__samples.parquet"))
    parser.add_argument("--warehouse", type=Path, default=Path("warehouse.duckdb"))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    load_id = str(uuid.uuid4())
    started_at = datetime.now(timezone.utc)

    con = duckdb.connect(str(args.warehouse))
    con.execute("""
        INSERT INTO ops.load_audit (load_id, source_table, source_uri, started_at, status)
        VALUES (?, 'raw_1kg__samples', ?, ?, 'running')
    """, [load_id, str(args.input), started_at])
    con.close()

    df = pd.read_csv(args.input, sep="\t")
    df.columns = [c.lower() for c in df.columns]
    df["load_id"] = load_id
    df["source_uri"] = str(args.input.resolve())
    df["ingested_at"] = started_at

    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(args.output, compression="zstd", index=False)

    finished_at = datetime.now(timezone.utc)
    con = duckdb.connect(str(args.warehouse))
    con.execute("""
        UPDATE ops.load_audit
        SET finished_at = ?, status = 'success', rows_loaded = ?
        WHERE load_id = ?
    """, [finished_at, len(df), load_id])
    con.close()

    logging.info(f"Wrote {len(df):,} samples to {args.output}")


if __name__ == "__main__":
    main()
EOF

# run it
python loader/panel_to_parquet.py
# 2026-05-25 21:35:37,174 [INFO] Wrote 2,504 samples to bronze/raw_1kg__samples.parquet

# verify
duckdb warehouse.duckdb -c "
  SELECT super_pop, count(*) AS n
  FROM read_parquet('bronze/raw_1kg__samples.parquet')
  GROUP BY super_pop
  ORDER BY n DESC
"
# ┌───────────┬───────┐
# │ super_pop │   n   │
# │  varchar  │ int64 │
# ├───────────┼───────┤
# │ AFR       │   661 │
# │ EAS       │   504 │
# │ EUR       │   503 │
# │ SAS       │   489 │
# │ AMR       │   347 │
# └───────────┴───────┘

# create loader/reference_to_parquet.py  (convert ref data)
cat > loader/reference_to_parquet.py <<'EOF'
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
EOF

# run it
python loader/reference_to_parquet.py
# 2026-05-25 21:38:52,120 [INFO] Parsing GENCODE: data/raw/ref/gencode_v44_chr22.gff3.gz
# 2026-05-25 21:38:52,174 [INFO] Wrote 1,445 rows to bronze/raw_ref__genes.parquet
# 2026-05-25 21:38:52,174 [INFO] Parsing ClinVar: data/raw/ref/clinvar_chr22.vcf.gz
# 2026-05-25 21:38:52,603 [INFO] Wrote 96,043 rows to bronze/raw_ref__clinvar.parquet

# Verify
duckdb warehouse.duckdb -c "
  SELECT count(*) AS gene_count FROM read_parquet('bronze/raw_ref__genes.parquet');
  SELECT count(*) AS clinvar_count FROM read_parquet('bronze/raw_ref__clinvar.parquet');
"
# ┌────────────┐
# │ gene_count │
# │   int64    │
# ├────────────┤
# │       1445 │
# └────────────┘
# ┌───────────────┐
# │ clinvar_count │
# │     int64     │
# ├───────────────┤
# │         96043 │
# └───────────────┘

# Full audit summary
duckdb warehouse.duckdb -c "
  SELECT source_table, status, rows_loaded, rows_failed,
         (epoch(finished_at) - epoch(started_at)) AS seconds
  FROM ops.load_audit
  ORDER BY started_at
"
# ┌───────────────────┬─────────┬─────────────┬─────────────┬──────────────────────┐
# │   source_table    │ status  │ rows_loaded │ rows_failed │       seconds        │
# │      varchar      │ varchar │    int64    │    int64    │        double        │
# ├───────────────────┼─────────┼─────────────┼─────────────┼──────────────────────┤
# │ raw_1kg__variants │ success │     4744579 │           0 │    287.4218170642853 │
# │ raw_1kg__variants │ success │           0 │           0 │  0.22816681861877441 │
# │ raw_1kg__variants │ success │     4744579 │           0 │    282.0643389225006 │
# │ raw_1kg__samples  │ success │        2504 │        NULL │ 0.025356054306030273 │
# │ raw_ref__genes    │ success │        1445 │        NULL │ 0.021075010299682617 │
# │ raw_ref__clinvar  │ success │       96043 │        NULL │ 0.038107872009277344 │
# └───────────────────┴─────────┴─────────────┴─────────────┴──────────────────────┘

# bronze/ is in .gitignore from Phase 0 — only commit scripts
git add loader/
git commit -m "Phase 2: Bronze loaders for VCF, panel, GENCODE, ClinVar (Parquet + audit)"
# sqlfluff-lint............................................................Passed
# [main f04961d] Phase 2: Bronze loaders for VCF, panel, GENCODE, ClinVar (Parquet + audit)
```
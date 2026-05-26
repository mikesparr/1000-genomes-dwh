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

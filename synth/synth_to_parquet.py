#!/usr/bin/env python3
"""
Convert the five synthetic CSVs into Bronze Parquet, with audit logging.
"""

import argparse
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path

import duckdb
import pandas as pd

CSVS = {
    "raw_synth__patients":         "patients.csv",
    "raw_synth__panels":           "panels.csv",
    "raw_synth__mrd_tests":        "mrd_tests.csv",
    "raw_synth__mrd_detections":   "mrd_detections.csv",
    "raw_synth__clinical_events":  "clinical_events.csv",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path("synth/output"))
    parser.add_argument("--bronze-dir", type=Path, default=Path("bronze"))
    parser.add_argument("--warehouse", type=Path, default=Path("warehouse.duckdb"))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    for table_name, csv_name in CSVS.items():
        csv_path = args.input_dir / csv_name
        if not csv_path.exists():
            logging.warning(f"Missing: {csv_path}")
            continue

        df = pd.read_csv(csv_path)
        load_id = str(uuid.uuid4())
        started_at = datetime.now(timezone.utc)

        con = duckdb.connect(str(args.warehouse))
        con.execute("""
            INSERT INTO ops.load_audit (load_id, source_table, source_uri, started_at, status)
            VALUES (?, ?, ?, ?, 'running')
        """, [load_id, table_name, str(csv_path.resolve()), started_at])
        con.close()

        df["load_id"] = load_id
        df["source_uri"] = str(csv_path.resolve())
        df["ingested_at"] = started_at
        out_path = args.bronze_dir / f"{table_name}.parquet"
        df.to_parquet(out_path, compression="zstd", index=False)

        finished_at = datetime.now(timezone.utc)
        con = duckdb.connect(str(args.warehouse))
        con.execute("""
            UPDATE ops.load_audit
            SET finished_at = ?, status = 'success', rows_loaded = ?
            WHERE load_id = ?
        """, [finished_at, len(df), load_id])
        con.close()

        logging.info(f"  {table_name}: {len(df):,} rows → {out_path}")


if __name__ == "__main__":
    main()

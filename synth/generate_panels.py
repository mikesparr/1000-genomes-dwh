#!/usr/bin/env python3
"""
Generate a personalized 16-variant 'panel' per patient.

Selection criteria (mimic Signatera's real assay-design logic):
  - SNVs only (panel positions are amplicon-sized, indels are harder to call)
  - PASS filter
  - Read depth >= 20 (for confidence)
  - Heterozygous in this patient's 1KG VCF (so it's a real signal, not artifact)
  - Spread across the chromosome (not all clustered in one region)

Deterministic from --seed (combined with patient_id for per-patient determinism).
"""

import argparse
import logging
import random
from pathlib import Path

import duckdb
import pandas as pd

PANEL_SIZE = 16
MIN_DEPTH = 20


def select_panel_for_patient(con, sample_id: str, panel_size: int, rng: random.Random):
    """Pick `panel_size` variants from this sample's bronze data meeting tumor-mimic criteria."""
    candidates = con.execute(f"""
        SELECT chromosome, position, ref_allele, alt_allele,
               variant_type, genotype, read_depth, variant_allele_freq
        FROM read_parquet('bronze/raw_1kg__variants/sample={sample_id}/*.parquet')
        WHERE variant_type = 'SNV'
          AND filter_status = 'PASS'
          AND read_depth >= {MIN_DEPTH}
          AND genotype IN ('0/1', '0|1', '1/0', '1|0')
        ORDER BY position
    """).fetchdf()

    if len(candidates) < panel_size:
        logging.warning(f"  {sample_id}: only {len(candidates)} candidates, returning all")
        return candidates

    # Spread across the chromosome: bin into panel_size buckets, take one from each
    candidates["bucket"] = pd.cut(candidates["position"], bins=panel_size, labels=False)
    selected = []
    for bucket_id in range(panel_size):
        bucket = candidates[candidates["bucket"] == bucket_id]
        if len(bucket) > 0:
            row_idx = rng.randint(0, len(bucket) - 1)
            selected.append(bucket.iloc[row_idx])

    # If some buckets were empty, top up randomly
    while len(selected) < panel_size:
        idx = rng.randint(0, len(candidates) - 1)
        row = candidates.iloc[idx]
        if not any((row["position"] == s["position"] and row["alt_allele"] == s["alt_allele"])
                   for s in selected):
            selected.append(row)

    return pd.DataFrame(selected).drop(columns=["bucket"], errors="ignore").reset_index(drop=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--warehouse", type=Path, default=Path("warehouse.duckdb"))
    parser.add_argument("--patients-csv", type=Path, default=Path("synth/output/patients.csv"))
    parser.add_argument("--output", type=Path, default=Path("synth/output/panels.csv"))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    patients = pd.read_csv(args.patients_csv)
    con = duckdb.connect(str(args.warehouse), read_only=True)

    rows = []
    for _, p in patients.iterrows():
        # Per-patient RNG: deterministic but unique
        prng = random.Random(args.seed + hash(p["patient_id"]) % 10**9)
        sample_id = p["sample_id_1kg"]

        panel = select_panel_for_patient(con, sample_id, PANEL_SIZE, prng)
        if len(panel) == 0:
            logging.warning(f"  {p['patient_id']}: NO candidates, skipping")
            continue

        # Simulated tumor VAF (germline VAF from 1KG is ~50%, tumor VAFs vary)
        for i, v in panel.iterrows():
            tumor_vaf = max(0.05, min(0.95, prng.gauss(0.45, 0.15)))
            rows.append({
                "panel_id": f"PNL-{p['patient_id']}",
                "patient_id": p["patient_id"],
                "variant_index": i,
                "chromosome": v["chromosome"],
                "position": int(v["position"]),
                "ref_allele": v["ref_allele"],
                "alt_allele": v["alt_allele"],
                "variant_key": f"{v['chromosome']}_{v['position']}_{v['ref_allele']}_{v['alt_allele']}",
                "simulated_tumor_vaf": round(tumor_vaf, 4),
                "panel_design_date": p["primary_surgery_date"],  # designed pre-surgery
            })

        logging.info(f"  {p['patient_id']}: panel of {len(panel)} variants")

    con.close()
    df = pd.DataFrame(rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    logging.info(f"Wrote {len(df)} panel rows ({df['patient_id'].nunique()} patients) to {args.output}")


if __name__ == "__main__":
    main()

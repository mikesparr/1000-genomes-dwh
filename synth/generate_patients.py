#!/usr/bin/env python3
"""
Generate synthetic patient demographics, anchored on real 1KG samples.

For each sample in the 1KG panel:
  - assign a tumor type weighted by realistic incidence
  - assign a stage at diagnosis (stratified by tumor type)
  - generate diagnosis date, surgery date, age at diagnosis
  - randomly enroll ~30% in a clinical trial
  - randomly mark 90% as 'consented for research'

Deterministic from --seed.
"""

import argparse
import json
import logging
import random
from datetime import date, timedelta
from pathlib import Path

import duckdb
import pandas as pd

# Realistic-ish tumor type incidence (rough US epidemiology)
TUMOR_TYPE_WEIGHTS = {
    "colorectal": 0.20,
    "breast": 0.18,
    "lung_nsclc": 0.15,
    "prostate": 0.12,
    "melanoma": 0.07,
    "pancreatic": 0.06,
    "ovarian": 0.05,
    "bladder": 0.05,
    "renal": 0.04,
    "gastric": 0.04,
    "head_and_neck": 0.04,
}

STAGE_WEIGHTS_BY_TUMOR = {
    "colorectal":      [0.15, 0.30, 0.35, 0.20],  # I, II, III, IV
    "breast":          [0.40, 0.30, 0.20, 0.10],
    "lung_nsclc":      [0.20, 0.20, 0.30, 0.30],
    "prostate":        [0.45, 0.25, 0.20, 0.10],
    "melanoma":        [0.50, 0.25, 0.15, 0.10],
    "pancreatic":      [0.10, 0.15, 0.30, 0.45],
    "ovarian":         [0.15, 0.15, 0.45, 0.25],
    "bladder":         [0.30, 0.30, 0.25, 0.15],
    "renal":           [0.40, 0.25, 0.20, 0.15],
    "gastric":         [0.20, 0.25, 0.30, 0.25],
    "head_and_neck":   [0.25, 0.25, 0.30, 0.20],
}

TRIALS = [
    {"trial_id": "NCT11111111", "name": "ADJUVO-1",   "tumor_types": ["colorectal", "gastric"]},
    {"trial_id": "NCT22222222", "name": "PRECISION-LUNG", "tumor_types": ["lung_nsclc"]},
    {"trial_id": "NCT33333333", "name": "MRDx-MULTI", "tumor_types": list(TUMOR_TYPE_WEIGHTS.keys())},
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--warehouse", type=Path, default=Path("warehouse.duckdb"))
    parser.add_argument("--output", type=Path, default=Path("synth/output/patients.csv"))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    rng = random.Random(args.seed)

    con = duckdb.connect(str(args.warehouse), read_only=True)
    samples = con.execute("""
        SELECT sample, pop, super_pop, gender
        FROM read_parquet('bronze/raw_1kg__samples.parquet')
    """).fetchdf()
    con.close()

    # Restrict to the 50 samples we actually fetched.
    # Each Bronze partition is a dir like "sample=HG00096"; we want the dir's OWN name.
    fetched = sorted({
        p.name.replace("sample=", "")
        for p in Path("bronze/raw_1kg__variants").glob("sample=*")
        if p.is_dir()
    })
    if not fetched:
        raise RuntimeError(
            "No fetched samples found under bronze/raw_1kg__variants/sample=*/. "
            "Did Phase 2.4 (vcf_to_parquet.py) complete successfully?"
        )
    samples = samples[samples["sample"].isin(fetched)].reset_index(drop=True)
    logging.info(f"Generating patients for {len(samples)} fetched 1KG samples")

    tumor_types = list(TUMOR_TYPE_WEIGHTS.keys())
    tumor_weights = list(TUMOR_TYPE_WEIGHTS.values())

    rows = []
    for _, s in samples.iterrows():
        tumor = rng.choices(tumor_types, weights=tumor_weights)[0]
        stage = rng.choices(["I", "II", "III", "IV"],
                            weights=STAGE_WEIGHTS_BY_TUMOR[tumor])[0]
        age_at_dx = rng.randint(40, 80)
        # Diagnosis date: spread across 2018-2023 so there's enough follow-up to recur
        dx_date = date(2018, 1, 1) + timedelta(days=rng.randint(0, 5 * 365))
        # Surgery typically 4-12 weeks after diagnosis
        surgery_date = dx_date + timedelta(days=rng.randint(28, 84))

        eligible_trials = [t for t in TRIALS if tumor in t["tumor_types"]]
        if rng.random() < 0.30 and eligible_trials:
            trial = rng.choice(eligible_trials)
            trial_id = trial["trial_id"]
            treatment_arm = rng.choice(["control", "experimental"])
        else:
            trial_id = None
            treatment_arm = None

        rows.append({
            "patient_id": f"PT-{s['sample']}",
            "sample_id_1kg": s["sample"],
            "tumor_type": tumor,
            "stage_at_diagnosis": stage,
            "age_at_diagnosis": age_at_dx,
            "sex_at_birth": s["gender"].lower() if s["gender"] else None,
            "ancestry_super_pop": s["super_pop"],
            "ancestry_pop": s["pop"],
            "diagnosis_date": dx_date,
            "primary_surgery_date": surgery_date,
            "trial_id": trial_id,
            "treatment_arm": treatment_arm,
            "consented_for_research": rng.random() < 0.90,
        })

    df = pd.DataFrame(rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    logging.info(f"Wrote {len(df)} patients to {args.output}")
    logging.info(f"Tumor type distribution:\n{df['tumor_type'].value_counts().to_string()}")


if __name__ == "__main__":
    main()

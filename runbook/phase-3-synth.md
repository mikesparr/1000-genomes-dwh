# Phase 3 - Synthetic Clinical & MRD Data Generation
**Goal:** generate realistic, internally-consistent synthetic clinical data on top of the real 1000 Genomes germline VCFs, producing five Bronze Parquet files: patients, panels, MRD tests, per-variant detections, and clinical events. Every output deterministic from a single seed so re-runs reproduce exactly.

## Commands (step-by-step)
```bash
#######################################################
# 3. SYNTHETIC CLINICAL & MRD DATA GENERATION
# - generate realistic, internally-consistent synthetic clinical data on top
#   of the 1000 Genomes germline VCFs, producing five Bronze Parquet files:
#   patients, panels, MRD tests, per-variant detections, and clinical events. 
#   Every output deterministic from a single seed so re-runs reproduce exactly.
#
# DESIGN
# - patient (grain: one row per 1KG sample) - tumor type, stage, diagnosis date, surgery date, trial
# - panel (grain: 16 rows per patient [16 chosen variants]) - each variant must exist in that patient's chr22 VCF
# - mrd_test (grain: one row per [patient x test_date]) - test event with timestamp, MTM/ml, positive flag
# - mrd_detection (grain: one row per [mrd_test x panel_variant]) - per-variant signal at each test event
# - clinical_event (grain: one row per [patient x event]) - diagnosis, surgery, chemo, imaging, recurrance
#######################################################

# create synth dir
mkdir -p synth
touch synth/__init__.py

# create synth/generate_patients.py
cat > synth/generate_patients.py <<'EOF'
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
EOF

# run it
python synth/generate_patients.py --seed 42
# 2026-05-25 21:51:40,448 [INFO] Generating patients for 50 fetched 1KG samples
# 2026-05-25 21:51:40,456 [INFO] Wrote 50 patients to synth/output/patients.csv
# 2026-05-25 21:51:40,457 [INFO] Tumor type distribution:
# tumor_type
# colorectal       15
# breast            9
# prostate          6
# melanoma          5
# lung_nsclc        5
# pancreatic        3
# renal             3
# head_and_neck     2
# ovarian           1
# bladder           1

# create synth/generate_panels.py
cat > synth/generate_panels.py <<'EOF'
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
EOF

# run it
python synth/generate_panels.py --seed 42
# ...
# 2026-05-25 21:53:44,896 [INFO]   PT-NA21133: panel of 16 variants
# 2026-05-25 21:53:44,904 [INFO] Wrote 800 panel rows (50 patients) to synth/output/panels.csv

# Verify: every patient should have exactly 16 panel variants
python -c "
import pandas as pd
df = pd.read_csv('synth/output/panels.csv')
print(df.groupby('patient_id').size().describe())
"
# count    50.0
# mean     16.0
# std       0.0
# min      16.0
# 25%      16.0
# 50%      16.0
# 75%      16.0
# max      16.0
# dtype: float64

# create synth/generate_trajectories.py
cat > synth/generate_trajectories.py <<'EOF'
#!/usr/bin/env python3
"""
Generate MRD test events, per-variant detection signals, and clinical events
along a stage-stratified Markov trajectory per patient.

States: 'MRD-' -> 'MRD+' -> 'recurred' (-> 'death' or 'censored')
"""

import argparse
import logging
import random
from datetime import date, timedelta
from pathlib import Path

import pandas as pd

# Per-test transition probabilities by stage (rough oncology priors)
# Probability of becoming MRD-positive at this test, given current state and stage
P_TURN_POSITIVE = {
    "I":   {"MRD-": 0.02},
    "II":  {"MRD-": 0.05},
    "III": {"MRD-": 0.12},
    "IV":  {"MRD-": 0.25},
}
# Probability of recurrence at this test once MRD-positive (given stage)
P_RECUR_GIVEN_POSITIVE = {
    "I":   0.30,
    "II":  0.45,
    "III": 0.60,
    "IV":  0.75,
}
# Median lead time (months) from first MRD+ to clinical recurrence
LEAD_TIME_MONTHS_BY_STAGE = {"I": 9, "II": 7, "III": 5, "IV": 3}

TEST_INTERVAL_DAYS = 90
MAX_FOLLOWUP_DAYS = 5 * 365


def generate_trajectory(patient, panel, rng):
    """Generate full trajectory for one patient. Returns (tests, detections, events)."""
    stage = patient["stage_at_diagnosis"]
    surgery = pd.to_datetime(patient["primary_surgery_date"]).date()
    pid = patient["patient_id"]

    tests, detections, events = [], [], []

    # Diagnosis + surgery clinical events
    events.append({
        "event_id": f"EV-{pid}-DX",
        "patient_id": pid,
        "event_date": pd.to_datetime(patient["diagnosis_date"]).date(),
        "event_type": "diagnosis",
        "event_subtype": patient["tumor_type"],
        "regimen": None,
        "outcome": None,
    })
    events.append({
        "event_id": f"EV-{pid}-SURG",
        "patient_id": pid,
        "event_date": surgery,
        "event_type": "surgery",
        "event_subtype": "primary_resection",
        "regimen": None,
        "outcome": None,
    })

    # Adjuvant chemo for stages II-IV with 70% probability
    if stage in ("II", "III", "IV") and rng.random() < 0.70:
        chemo_start = surgery + timedelta(days=rng.randint(28, 56))
        events.append({
            "event_id": f"EV-{pid}-CHEMO",
            "patient_id": pid,
            "event_date": chemo_start,
            "event_type": "chemotherapy_start",
            "event_subtype": "adjuvant",
            "regimen": rng.choice(["FOLFOX", "FOLFIRI", "CAPEOX", "AC-T", "FOLFIRINOX"]),
            "outcome": None,
        })

    # MRD trajectory
    state = "MRD-"
    test_date = surgery + timedelta(days=TEST_INTERVAL_DAYS)
    end_date = surgery + timedelta(days=MAX_FOLLOWUP_DAYS)
    test_seq = 0
    first_positive_date = None

    while test_date <= end_date and state != "recurred":
        test_seq += 1
        days_since_surgery = (test_date - surgery).days

        if state == "MRD-":
            if rng.random() < P_TURN_POSITIVE[stage]["MRD-"]:
                state = "MRD+"

        # MTM/mL: simulate tumor signal
        if state == "MRD+":
            mtm = round(rng.lognormvariate(-1.5, 1.2), 4)  # skewed toward small values
            mtm = max(0.001, min(50.0, mtm))
            is_positive = True
            if first_positive_date is None:
                first_positive_date = test_date
        else:
            mtm = 0.0
            is_positive = False

        test_id = f"MRD-{pid}-{test_seq:03d}"
        tests.append({
            "test_id": test_id,
            "patient_id": pid,
            "panel_id": f"PNL-{pid}",
            "test_date": test_date,
            "test_sequence_number": test_seq,
            "days_since_surgery": days_since_surgery,
            "is_positive": is_positive,
            "mtm_per_ml": mtm,
        })

        # Per-variant detection rows: when MRD+, ~30-70% of panel variants show signal
        patient_panel = panel[panel["patient_id"] == pid]
        for _, v in patient_panel.iterrows():
            if is_positive and rng.random() < rng.uniform(0.3, 0.7):
                vaf_blood = round(rng.uniform(0.0001, 0.005), 6)
                detected = True
            else:
                vaf_blood = 0.0
                detected = False
            detections.append({
                "detection_id": f"DET-{test_id}-{v['variant_index']}",
                "test_id": test_id,
                "patient_id": pid,
                "variant_key": v["variant_key"],
                "vaf_blood": vaf_blood,
                "is_detected": detected,
            })

        # Recurrence check: once MRD+, accumulate hazard
        if state == "MRD+" and first_positive_date:
            months_since_positive = (test_date - first_positive_date).days / 30.0
            lead_time = LEAD_TIME_MONTHS_BY_STAGE[stage]
            if months_since_positive >= lead_time and rng.random() < P_RECUR_GIVEN_POSITIVE[stage]:
                state = "recurred"
                events.append({
                    "event_id": f"EV-{pid}-RECUR",
                    "patient_id": pid,
                    "event_date": test_date,
                    "event_type": "recurrence",
                    "event_subtype": "metastatic" if rng.random() < 0.60 else "local",
                    "regimen": None,
                    "outcome": None,
                })

        test_date += timedelta(days=TEST_INTERVAL_DAYS)

    return tests, detections, events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--patients-csv", type=Path, default=Path("synth/output/patients.csv"))
    parser.add_argument("--panels-csv", type=Path, default=Path("synth/output/panels.csv"))
    parser.add_argument("--output-dir", type=Path, default=Path("synth/output"))
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    patients = pd.read_csv(args.patients_csv)
    panels = pd.read_csv(args.panels_csv)
    logging.info(f"Generating trajectories for {len(patients)} patients")

    all_tests, all_detections, all_events = [], [], []
    for _, p in patients.iterrows():
        prng = random.Random(args.seed + hash(p["patient_id"]) % 10**9)
        t, d, e = generate_trajectory(p, panels, prng)
        all_tests.extend(t)
        all_detections.extend(d)
        all_events.extend(e)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(all_tests).to_csv(args.output_dir / "mrd_tests.csv", index=False)
    pd.DataFrame(all_detections).to_csv(args.output_dir / "mrd_detections.csv", index=False)
    pd.DataFrame(all_events).to_csv(args.output_dir / "clinical_events.csv", index=False)

    logging.info(f"  {len(all_tests):,} tests")
    logging.info(f"  {len(all_detections):,} detections")
    logging.info(f"  {len(all_events):,} clinical events")


if __name__ == "__main__":
    main()
EOF

# run it
python synth/generate_trajectories.py --seed 42
# 2026-05-25 22:02:11,414 [INFO] Generating trajectories for 50 patients
# 2026-05-25 22:02:11,653 [INFO]   666 tests
# 2026-05-25 22:02:11,653 [INFO]   10,656 detections
# 2026-05-25 22:02:11,653 [INFO]   151 clinical events

ls -lh synth/output/
# patients.csv  panels.csv  mrd_tests.csv  mrd_detections.csv  clinical_events.csv

# create synth/synth_to_parquet.py (land synthetic data into Bronze)
cat > synth/synth_to_parquet.py <<'EOF'
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
EOF

# run it
python synth/synth_to_parquet.py
# 2026-05-25 22:05:00,381 [INFO]   raw_synth__patients: 50 rows → bronze/raw_synth__patients.parquet
# 2026-05-25 22:05:00,398 [INFO]   raw_synth__panels: 800 rows → bronze/raw_synth__panels.parquet
# 2026-05-25 22:05:00,415 [INFO]   raw_synth__mrd_tests: 666 rows → bronze/raw_synth__mrd_tests.parquet
# 2026-05-25 22:05:00,440 [INFO]   raw_synth__mrd_detections: 10,656 rows → bronze/raw_synth__mrd_detections.parquet
# 2026-05-25 22:05:00,456 [INFO]   raw_synth__clinical_events: 151 rows → bronze/raw_synth__clinical_events.parquet

# Verify internal consistency (dbt test dress rehearsals; fix before moving on)
duckdb warehouse.duckdb <<'SQL'
-- 1. Every patient has 16 panel variants
SELECT
  count(*) AS patient_count,
  count(*) FILTER (WHERE variant_count != 16) AS bad
FROM (
  SELECT patient_id, count(*) AS variant_count
  FROM read_parquet('bronze/raw_synth__panels.parquet')
  GROUP BY patient_id
);

-- 2. Every panel variant_key exists in that patient's chr22 1KG VCF
WITH panel_keys AS (
  SELECT p.patient_id, p.variant_key, pt.sample_id_1kg
  FROM read_parquet('bronze/raw_synth__panels.parquet') p
  JOIN read_parquet('bronze/raw_synth__patients.parquet') pt USING (patient_id)
),
variant_keys AS (
  SELECT
    sample_id,
    chromosome || '_' || position || '_' || ref_allele || '_' || alt_allele AS variant_key
  FROM read_parquet('bronze/raw_1kg__variants/**/*.parquet', hive_partitioning=true)
)
SELECT
  count(*) AS panel_variants,
  count(*) FILTER (WHERE v.variant_key IS NULL) AS orphans
FROM panel_keys p
LEFT JOIN variant_keys v
  ON v.sample_id = p.sample_id_1kg AND v.variant_key = p.variant_key;

-- 3. No MRD-positive test before surgery
SELECT count(*) AS bad
FROM read_parquet('bronze/raw_synth__mrd_tests.parquet') t
JOIN read_parquet('bronze/raw_synth__patients.parquet') p USING (patient_id)
WHERE t.is_positive AND t.test_date < p.primary_surgery_date;

-- 4. Test dates monotonic per patient
WITH ordered AS (
  SELECT patient_id, test_date,
         lag(test_date) OVER (PARTITION BY patient_id ORDER BY test_date) AS prev_date
  FROM read_parquet('bronze/raw_synth__mrd_tests.parquet')
)
SELECT count(*) AS bad FROM ordered WHERE prev_date IS NOT NULL AND test_date <= prev_date;

-- 5. MRD positivity rate by stage (sanity check the Markov model)
SELECT p.stage_at_diagnosis,
       count(DISTINCT t.test_id) AS tests,
       sum(CASE WHEN t.is_positive THEN 1 ELSE 0 END) AS positive_tests,
       round(100.0 * sum(CASE WHEN t.is_positive THEN 1 ELSE 0 END) / count(*), 1) AS pct_positive
FROM read_parquet('bronze/raw_synth__mrd_tests.parquet') t
JOIN read_parquet('bronze/raw_synth__patients.parquet') p USING (patient_id)
GROUP BY 1
ORDER BY 1;
SQL

# ┌───────────────┬───────┐
# │ patient_count │  bad  │
# │     int64     │ int64 │
# ├───────────────┼───────┤
# │            50 │     0 │
# └───────────────┴───────┘
# ┌────────────────┬─────────┐
# │ panel_variants │ orphans │
# │     int64      │  int64  │
# ├────────────────┼─────────┤
# │            800 │       0 │
# └────────────────┴─────────┘
# ┌───────┐
# │  bad  │
# │ int64 │
# ├───────┤
# │     0 │
# └───────┘
# ┌───────┐
# │  bad  │
# │ int64 │
# ├───────┤
# │     0 │
# └───────┘
# ┌────────────────────┬───────┬────────────────┬──────────────┐
# │ stage_at_diagnosis │ tests │ positive_tests │ pct_positive │
# │      varchar       │ int64 │     int128     │    double    │
# ├────────────────────┼───────┼────────────────┼──────────────┤
# │ I                  │   309 │             35 │         11.3 │
# │ II                 │   143 │             23 │         16.1 │
# │ III                │   170 │             52 │         30.6 │
# │ IV                 │    44 │             24 │         54.5 │
# └────────────────────┴───────┴────────────────┴──────────────┘

# synth/output/ should be gitignored alongside data/raw/. Add it to .gitignore:
echo "synth/output/" >> .gitignore
git add synth/ .gitignore
git commit -m "Phase 3: synthetic clinical and MRD trajectory generators"
```
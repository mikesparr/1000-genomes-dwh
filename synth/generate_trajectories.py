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

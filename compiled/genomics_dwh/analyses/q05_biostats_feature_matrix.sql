-- analyses/q05_biostats_feature_matrix.sql
--
-- Persona: Biostats / ML
-- Question: "Build a feature matrix: per patient, baseline panel size,
--            baseline ctDNA status, treatment arm, time-to-recurrence"
--
-- Demonstrates: the "wide" feature shape ML pipelines want — one row per patient,
-- every feature as a column. The pharma cohort extract already does most of this
-- work because it's designed for downstream model training; here we shape the
-- output specifically for survival modeling (lifelines / R survival package input).
--
-- Output schema is intentionally close to scikit-learn / lifelines input format:
-- numeric and categorical features + (event_observed, time_to_event) for survival.
--
-- Note on panel_size: this project's panel generator produces exactly 16 variants
-- per patient by design, so it's a constant in this dataset. In a production
-- system with variable panel sizes, the right fix is to add panel_size as a
-- column to mart_clin__patient_timeline (so it propagates through to the
-- pharma extract), not to join dim_panel here — the pharma extract masks
-- patient_sk via md5(), making downstream joins back to dim_panel impossible
-- by design.
--
-- Run: dbt show --select q05_biostats_feature_matrix --limit 25

with cohort as (
    select * from "ci_warehouse"."main"."mart_pharma__cohort_extract"
)

select
    c.patient_sk_masked,
    -- Demographic features
    c.age_at_diagnosis,
    c.sex_at_birth,
    c.ancestry_super_population,
    -- Disease features
    c.tumor_type,
    c.stage_at_diagnosis,
    -- Treatment features
    c.trial_id,
    c.treatment_arm,
    -- Panel / assay design feature (constant 16 in this project's design)
    16 as baseline_panel_size,
    -- MRD trajectory features (early signals usable as ML features)
    cast(c.mrd_status_d90 as integer) as mrd_status_d90_int,
    cast(c.mrd_status_d180 as integer) as mrd_status_d180_int,
    cast(c.mrd_status_d365 as integer) as mrd_status_d365_int,
    -- Survival analysis target columns (lifelines / survival package input)
    -- event_observed = 1 if recurrence occurred, 0 if censored
    cast(c.has_recurred as integer) as event_observed,
    -- time_to_event = days_to_recurrence if it occurred,
    -- else days from last_test_date to surgery (the follow-up window)
    -- Note: in a real system you'd use the patient's primary_surgery_date as
    -- the anchor and last_test_date as the censor point; the pharma extract
    -- intentionally doesn't expose primary_surgery_date (privacy), so the
    -- censor calculation has to be done upstream in the timeline mart.
    c.days_to_recurrence as time_to_event_days,
    -- Outcome at common landmarks (for binary classification targets)
    c.recurrence_within_2yr,
    c.event_status
from cohort as c
order by c.patient_sk_masked
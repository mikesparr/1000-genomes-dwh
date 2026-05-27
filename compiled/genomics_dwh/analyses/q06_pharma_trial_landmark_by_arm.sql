-- analyses/q06_pharma_trial_landmark_by_arm.sql
--
-- Persona: Pharma Partner
-- Question: "For trial NCT11111111 (ADJUVO-1), give me MRD landmark status at
--            day 90 stratified by treatment arm"
--
-- Demonstrates: trial-scoped, governance-aware analytical extraction.
--   - Reads ONLY from mart_pharma__cohort_extract (already filtered to consented
--     patients in Phase 6.9 — non-consented patients are technically unreachable)
--   - Patient identifiers are pre-masked (patient_sk_masked) — pharma sees no PHI
--   - Stratification by treatment_arm is the standard primary endpoint shape
--
-- This is the canonical "data delivery to a clinical trial sponsor" query. In
-- production, this would be the body of a stored proc / scheduled extract that
-- pharma reads via a Snowflake share or governed view.
--
-- Run: dbt show --select q06_pharma_trial_landmark_by_arm --limit 50

with trial_cohort as (
    select * from "ci_warehouse"."main"."mart_pharma__cohort_extract"
    where trial_id = 'NCT11111111'  -- ADJUVO-1; substitute as needed
)

select
    trial_id,
    treatment_arm,
    tumor_type,
    stage_at_diagnosis,
    count(*) as n_enrolled,
    -- Day 90 MRD outcomes
    sum(case when mrd_status_d90 = true then 1 else 0 end) as positive_d90,
    sum(case when mrd_status_d90 = false then 1 else 0 end) as negative_d90,
    sum(case when mrd_status_d90 is null then 1 else 0 end) as not_evaluable_d90,
    round(
        100.0 * sum(case when mrd_status_d90 = true then 1 else 0 end)
        / nullif(sum(case when mrd_status_d90 is not null then 1 else 0 end), 0),
        1
    ) as pct_positive_d90,
    -- Recurrence outcome through 2 years
    sum(case when recurrence_within_2yr = true then 1 else 0 end) as recurred_within_2yr,
    round(
        100.0 * sum(case when recurrence_within_2yr = true then 1 else 0 end)
        / nullif(count(*), 0),
        1
    ) as pct_recurred_within_2yr,
    -- Median time-to-recurrence among recurrers
    median(case when recurrence_within_2yr then days_to_recurrence end)
        as median_days_to_recurrence
from trial_cohort
group by trial_id, treatment_arm, tumor_type, stage_at_diagnosis
order by trial_id, treatment_arm, tumor_type, stage_at_diagnosis
-- analyses/q04_mrd_lead_time_analysis.sql
--
-- Persona: Clinical Analyst
-- Question: "Show me patients who turned MRD+ before clinical recurrence —
--            what was the lead time?"
--
-- Demonstrates: the headline value proposition of MRD testing — *predicting*
-- recurrence months before imaging or symptoms can. Lead time is the days between
-- first MRD-positive test and the eventual clinical recurrence event, computed
-- per-patient and stratified by stage.
--
-- This is what oncologists cite when explaining why MRD assays change clinical
-- practice. It's also one of the trial endpoints regulators care most about.
--
-- Run: dbt show --select q04_mrd_lead_time_analysis --limit 50

with patients_with_lead_time as (
    select
        patient_sk,
        tumor_type,
        stage_at_diagnosis,
        treatment_arm,
        first_positive_date,
        first_recurrence_date,
        mrd_lead_time_days
    from "ci_warehouse"."main"."mart_clin__patient_timeline"
    where
        has_recurred
        and mrd_lead_time_days is not null
        and mrd_lead_time_days > 0   -- exclude patients where MRD+ came after recurrence
)

select
    stage_at_diagnosis,
    count(*) as n_patients,
    round(avg(mrd_lead_time_days), 1) as avg_lead_days,
    median(mrd_lead_time_days) as median_lead_days,
    min(mrd_lead_time_days) as min_lead_days,
    max(mrd_lead_time_days) as max_lead_days,
    -- Convert to months for clinical interpretability
    round(avg(mrd_lead_time_days) / 30.0, 1) as avg_lead_months,
    round(median(mrd_lead_time_days) / 30.0, 1) as median_lead_months,
    -- Quartiles for distribution shape
    quantile_cont(mrd_lead_time_days, 0.25) as q1_lead_days,
    quantile_cont(mrd_lead_time_days, 0.75) as q3_lead_days
from patients_with_lead_time
group by stage_at_diagnosis
order by stage_at_diagnosis
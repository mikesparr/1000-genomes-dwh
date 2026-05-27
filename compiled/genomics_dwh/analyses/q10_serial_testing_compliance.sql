-- analyses/q10_serial_testing_compliance.sql
--
-- Persona: Clinical Analyst
-- Question: "What % of patients have at least 4 serial tests by the 12-month
--            landmark?"
--
-- Demonstrates: a self-service dashboard query that's pure aggregation against
-- the patient timeline mart. Operational metric — serial-testing compliance is
-- one of the things commercial teams track to gauge product adoption and
-- protocol adherence. Stratified by tumor type so different disease-area teams
-- can see their own numbers.
--
-- Run: dbt show --select q10_serial_testing_compliance --limit 50

with patients_at_12mo as (
    select
        patient_sk,
        tumor_type,
        stage_at_diagnosis,
        treatment_arm,
        total_test_count,
        date_diff('day', primary_surgery_date, last_test_date) as days_followed,
        -- Count tests within the first 365 days post-surgery; patients still
        -- being followed past 365d count as having reached the 12mo landmark
        coalesce(date_diff('day', primary_surgery_date, last_test_date) >= 335, false) as reached_12mo_followup
    from "ci_warehouse"."main"."mart_clin__patient_timeline"
    where primary_surgery_date is not null
),

eligible as (
    -- Only count compliance among patients who had a chance to hit 12mo
    select * from patients_at_12mo
    where reached_12mo_followup
)

select
    tumor_type,
    stage_at_diagnosis,
    count(*) as n_eligible_patients,
    sum(case when total_test_count >= 4 then 1 else 0 end) as n_compliant,
    sum(case when total_test_count >= 4 then 1 else 0 end) * 100.0
    / nullif(count(*), 0)
        as pct_compliant,
    round(avg(total_test_count), 1) as avg_tests_per_patient,
    median(total_test_count) as median_tests_per_patient,
    min(total_test_count) as min_tests,
    max(total_test_count) as max_tests
from eligible
group by tumor_type, stage_at_diagnosis
order by tumor_type, stage_at_diagnosis
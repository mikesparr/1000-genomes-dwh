-- analyses/q03_mrd_positivity_by_landmark.sql
--
-- Persona: Clinical Analyst
-- Question: "MRD positivity rate at 90 / 180 / 365 / 730 days post-surgery,
--            by tumor type and stage at diagnosis"
--
-- Demonstrates: the OBT mart paying off — zero joins, reads only from
-- mart_clin__patient_timeline because all landmark statuses were pre-pivoted
-- in Phase 6.8. This is exactly the query a Tableau/Looker dashboard would issue.
--
-- Run: dbt show --select q03_mrd_positivity_by_landmark --limit 50

select
    tumor_type,
    stage_at_diagnosis,
    count(*) as n_patients,
    -- Day 90 landmark
    sum(case when mrd_status_d90 = true then 1 else 0 end) as positive_d90,
    sum(case when mrd_status_d90 is not null then 1 else 0 end) as evaluable_d90,
    round(
        100.0 * sum(case when mrd_status_d90 = true then 1 else 0 end)
        / nullif(sum(case when mrd_status_d90 is not null then 1 else 0 end), 0),
        1
    ) as pct_positive_d90,
    -- Day 180 landmark
    sum(case when mrd_status_d180 = true then 1 else 0 end) as positive_d180,
    sum(case when mrd_status_d180 is not null then 1 else 0 end) as evaluable_d180,
    round(
        100.0 * sum(case when mrd_status_d180 = true then 1 else 0 end)
        / nullif(sum(case when mrd_status_d180 is not null then 1 else 0 end), 0),
        1
    ) as pct_positive_d180,
    -- Day 365 landmark
    sum(case when mrd_status_d365 = true then 1 else 0 end) as positive_d365,
    sum(case when mrd_status_d365 is not null then 1 else 0 end) as evaluable_d365,
    round(
        100.0 * sum(case when mrd_status_d365 = true then 1 else 0 end)
        / nullif(sum(case when mrd_status_d365 is not null then 1 else 0 end), 0),
        1
    ) as pct_positive_d365,
    -- Day 730 landmark (2-year)
    sum(case when mrd_status_d730 = true then 1 else 0 end) as positive_d730,
    sum(case when mrd_status_d730 is not null then 1 else 0 end) as evaluable_d730,
    round(
        100.0 * sum(case when mrd_status_d730 = true then 1 else 0 end)
        / nullif(sum(case when mrd_status_d730 is not null then 1 else 0 end), 0),
        1
    ) as pct_positive_d730
from "ci_warehouse"."main"."mart_clin__patient_timeline"
group by tumor_type, stage_at_diagnosis
order by tumor_type, stage_at_diagnosis
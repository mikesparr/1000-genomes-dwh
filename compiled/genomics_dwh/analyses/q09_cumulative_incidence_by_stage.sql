-- analyses/q09_cumulative_incidence_by_stage.sql
--
-- Persona: Biostats / ML
-- Question: "Cumulative incidence of recurrence by stage, censored at last visit"
--
-- Demonstrates: time-to-event analysis fundamentals — censoring, cumulative
-- incidence, stage stratification. This is the data shape the biostats team
-- feeds into Kaplan-Meier curves (`survfit` in R, `lifelines` in Python).
--
-- Outputs one row per (stage, time_window) showing how many patients had recurred
-- by that point and how many were still being followed (at-risk). The biostats
-- team takes this and computes survival curves; we don't compute KM math in SQL
-- (it's a numerical algorithm with non-trivial edge cases) — we hand them the
-- right *shape*.
--
-- Run: dbt show --select q09_cumulative_incidence_by_stage --limit 100

with patient_outcomes as (
    select
        patient_sk,
        stage_at_diagnosis,
        primary_surgery_date,
        first_recurrence_date,
        last_test_date,
        has_recurred,
        days_to_recurrence,
        case
            when has_recurred then days_to_recurrence
            else date_diff('day', primary_surgery_date, last_test_date)
        end as time_to_event_or_censor_days,
        cast(has_recurred as integer) as event_observed
    from "ci_warehouse"."main"."mart_clin__patient_timeline"
    where primary_surgery_date is not null
),

-- Generate landmark windows at clinically-relevant intervals
landmarks as (
    select unnest([90, 180, 365, 540, 730, 1095]) as landmark_days
),

-- For each (stage, landmark), count events that occurred by that point
-- and patients still at risk (followed past the landmark)
stage_landmark_grid as (
    select
        po.stage_at_diagnosis,
        l.landmark_days,
        count(*) filter (
            where po.event_observed = 1
            and po.time_to_event_or_censor_days <= l.landmark_days
        ) as cumulative_events,
        count(*) filter (
            where po.time_to_event_or_censor_days >= l.landmark_days
        ) as at_risk_at_landmark,
        count(*) as total_in_stage
    from patient_outcomes as po
    cross join landmarks as l
    group by po.stage_at_diagnosis, l.landmark_days
)

select
    stage_at_diagnosis,
    landmark_days,
    round(landmark_days / 30.0, 1) as landmark_months,
    cumulative_events,
    at_risk_at_landmark,
    total_in_stage,
    -- Crude cumulative incidence (events / total at start)
    round(100.0 * cumulative_events / nullif(total_in_stage, 0), 1)
        as crude_cumulative_incidence_pct,
    -- Percent still at risk (informs how trustworthy the estimate is)
    round(100.0 * at_risk_at_landmark / nullif(total_in_stage, 0), 1)
        as pct_at_risk_at_landmark
from stage_landmark_grid
order by stage_at_diagnosis, landmark_days
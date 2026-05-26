-- analyses/q07_clin_ops_pending_tests.sql
--
-- Persona: Clinical Operations
-- Question: "How many tests are pending result delivery > 7 days?"
--
-- Demonstrates: an operational-dashboard query — the kind of thing that runs
-- every 15 minutes and powers a "production health" dashboard for the lab ops
-- team. Filters narrow to recent tests, so clustering on test_date is doing
-- 99% of the I/O reduction work.
--
-- In our synthetic data we don't model "pending" status explicitly — every test
-- has a result. So we approximate by looking at the *latest* test per patient
-- and counting those where the most recent test was >7 days ago without a
-- subsequent test being scheduled. In a real production warehouse you'd have
-- a `test_status` column with values like 'collected', 'in_lab', 'reported'.
--
-- Run: dbt show --select q07_clin_ops_pending_tests --limit 50

with latest_test_per_patient as (
    select
        patient_sk,
        max(test_date) as last_test_date,
        max(test_sequence_number) as last_test_sequence
    from {{ ref('fct_mrd_test') }}
    -- Production: filter to last 30 days for partition pruning
    where test_date >= current_date - interval '180 days'
    group by patient_sk
),

stale_tests as (
    select
        patient_sk,
        last_test_date,
        last_test_sequence,
        date_diff('day', last_test_date, current_date) as days_since_last_test
    from latest_test_per_patient
    where date_diff('day', last_test_date, current_date) > 7
)

select
    -- Buckets clinical ops cares about
    case
        when days_since_last_test between 8 and 14 then '08-14 days'
        when days_since_last_test between 15 and 30 then '15-30 days'
        when days_since_last_test between 31 and 60 then '31-60 days'
        else '> 60 days'
    end as bucket,
    count(*) as n_patients,
    min(last_test_date) as oldest_test_date,
    max(last_test_date) as newest_test_date,
    round(avg(days_since_last_test), 0) as avg_days_pending
from stale_tests
group by bucket
order by min(days_since_last_test)

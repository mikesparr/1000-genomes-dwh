with ordered as (
    select
        patient_id,
        test_date,
        lag(test_date) over (partition by patient_id order by test_date) as prev_test_date
    from {{ ref('int_mrd__test_with_panel') }}
)

select *
from ordered
where
    prev_test_date is not null
    and test_date <= prev_test_date

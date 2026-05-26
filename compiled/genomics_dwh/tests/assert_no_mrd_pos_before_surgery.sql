-- Returns rows that VIOLATE the rule (the test fails if it returns any rows)
select
    t.test_id,
    t.patient_id,
    t.test_date,
    t.primary_surgery_date
from "ci_warehouse"."main"."int_mrd__test_with_panel" as t
where
    t.is_positive
    and t.test_date < t.primary_surgery_date
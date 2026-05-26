{{ config(materialized='table') }}

with snap as (
    select * from {{ ref('snap_dim_patient') }}
)

select
    {{ make_surrogate_key(['patient_id', 'dbt_valid_from']) }} as patient_sk,
    patient_id,
    sample_id_1kg,
    tumor_type,
    stage_at_diagnosis,
    age_at_diagnosis,
    sex_at_birth,
    ancestry_super_population,
    ancestry_population_code,
    diagnosis_date,
    primary_surgery_date,
    trial_id,
    treatment_arm,
    consented_for_research,
    dbt_valid_from as eff_from,
    coalesce(dbt_valid_to, cast('9999-12-31' as date)) as eff_to,
    dbt_valid_to is null as is_current
from snap

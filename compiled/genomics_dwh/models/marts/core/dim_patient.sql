

with snap as (
    select * from "ci_warehouse"."snapshots"."snap_dim_patient"
)

select
    
    md5(
      coalesce(cast(patient_id as varchar), '_NULL_') || '_' || coalesce(cast(dbt_valid_from as varchar), '_NULL_')
    )
 as patient_sk,
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
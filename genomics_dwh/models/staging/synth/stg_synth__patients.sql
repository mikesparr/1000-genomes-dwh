{{ config(materialized='view') }}

with source as (
    select * from {{ source('bronze', 'raw_synth__patients') }}
),

renamed as (
    select
        patient_id,
        sample_id_1kg,
        tumor_type,
        stage_at_diagnosis,
        cast(age_at_diagnosis as integer) as age_at_diagnosis,
        sex_at_birth,
        ancestry_super_pop as ancestry_super_population,
        ancestry_pop as ancestry_population_code,
        cast(diagnosis_date as date) as diagnosis_date,
        cast(primary_surgery_date as date) as primary_surgery_date,
        trial_id,
        treatment_arm,
        cast(consented_for_research as boolean) as consented_for_research,
        load_id,
        ingested_at
    from source
)

select * from renamed

{% snapshot snap_dim_patient %}

    {{
        config(
          target_schema='snapshots',
          unique_key='patient_id',
          strategy='check',
          check_cols=['tumor_type', 'stage_at_diagnosis', 'trial_id', 'treatment_arm']
        )
    }}

    select
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
        consented_for_research
    from {{ ref('int_patients__panel_designed') }}

{% endsnapshot %}

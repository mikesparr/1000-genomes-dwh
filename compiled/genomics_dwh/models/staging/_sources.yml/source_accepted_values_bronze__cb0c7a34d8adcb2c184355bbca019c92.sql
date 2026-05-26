
    
    

with all_values as (

    select
        stage_at_diagnosis as value_field,
        count(*) as n_records

    from read_parquet('../bronze/raw_synth__patients.parquet')
    group by stage_at_diagnosis

)

select *
from all_values
where value_field not in (
    'I','II','III','IV'
)



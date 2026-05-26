{{ config(materialized='table') }}

select distinct
    {{ make_surrogate_key(['population_code']) }} as population_sk,
    super_population,
    population_code,
    case super_population
        when 'AFR' then 'African'
        when 'AMR' then 'Admixed American'
        when 'EAS' then 'East Asian'
        when 'EUR' then 'European'
        when 'SAS' then 'South Asian'
    end as super_population_name
from {{ ref('stg_1kg__samples') }}

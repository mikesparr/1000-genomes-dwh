{{ config(materialized='table') }}

with date_spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2015-01-01' as date)",
        end_date="cast('2030-12-31' as date)"
    ) }}
)

select
    cast(date_day as date) as date_sk,
    cast(date_day as date) as full_date,
    extract(year from date_day) as year,
    extract(quarter from date_day) as quarter,
    extract(month from date_day) as month_num,
    extract(day from date_day) as day_of_month,
    extract(dow from date_day) as day_of_week_num,
    strftime(date_day, '%A') as day_of_week_name,
    not coalesce(extract(dow from date_day) in (0, 6), false) as is_business_day
from date_spine


    
    

select
    sample as unique_field,
    count(*) as n_records

from read_parquet('../bronze/raw_1kg__samples.parquet')
where sample is not null
group by sample
having count(*) > 1



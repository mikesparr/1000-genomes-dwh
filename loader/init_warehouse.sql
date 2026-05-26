-- loader/init_warehouse.sql
-- Idempotent warehouse initialization. Safe to re-run.

create schema if not exists bronze;
create schema if not exists ops;

create table if not exists ops.load_audit (
    load_id varchar primary key,
    source_table varchar not null,    -- e.g. 'raw_1kg__variants'
    source_uri varchar,               -- file or S3 URI
    started_at timestamp not null,
    finished_at timestamp,
    status varchar not null,          -- 'running', 'success', 'failed'
    rows_loaded bigint,
    rows_failed bigint,
    error_message varchar
);

create index if not exists idx_load_audit_table on ops.load_audit (source_table);
create index if not exists idx_load_audit_status on ops.load_audit (status);

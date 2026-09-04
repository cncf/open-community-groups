-- Inserts one row built from a jsonb object, keeping table defaults for absent columns.
create or replace function fx_insert_row(p_table regclass, p_row jsonb)
returns void as $$
declare
    v_columns text;
begin
    -- Unknown keys fail as unknown columns instead of being silently ignored
    select string_agg(quote_ident(key), ', ' order by key)
    into v_columns
    from jsonb_object_keys(p_row) as key;

    execute format(
        'insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)',
        p_table,
        v_columns,
        v_columns,
        p_table
    ) using p_row;
end;
$$ language plpgsql;

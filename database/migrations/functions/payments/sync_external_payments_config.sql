-- Upserts or deletes the single external-payments configuration row.
create or replace function sync_external_payments_config(
    p_allowed_countries text[],
    p_default_payment_window_hours int,
    p_max_payment_window_hours int
)
returns void as $$
declare
    v_allowed_countries text[];
begin
    -- Delete the row when the operator removed the configuration section
    if p_allowed_countries is null then
        delete from external_payments_config;
        return;
    end if;

    -- Normalize allowlisted country codes before replacing the singleton row
    select array_agg(distinct upper(btrim(code)) order by upper(btrim(code)))
    into v_allowed_countries
    from unnest(p_allowed_countries) as code
    where btrim(code) <> '';

    -- Replace the single config row with the current operator values
    insert into external_payments_config (
        singleton,
        allowed_countries,
        default_payment_window_hours,
        max_payment_window_hours,
        updated_at
    ) values (
        true,
        v_allowed_countries,
        p_default_payment_window_hours,
        p_max_payment_window_hours,
        current_timestamp
    )
    on conflict (singleton) do update
    set
        allowed_countries = excluded.allowed_countries,
        default_payment_window_hours = excluded.default_payment_window_hours,
        max_payment_window_hours = excluded.max_payment_window_hours,
        updated_at = current_timestamp;
end;
$$ language plpgsql;

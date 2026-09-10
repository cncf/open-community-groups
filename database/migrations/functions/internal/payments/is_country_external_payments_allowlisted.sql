-- Returns whether a country is on the operator external-payments allowlist.
create or replace function is_country_external_payments_allowlisted(
    p_country_code text
)
returns boolean as $$
    select exists (
        select 1
        from external_payments_config cfg
        where cfg.singleton
        and upper(nullif(btrim(p_country_code), '')) = any(cfg.allowed_countries)
    );
$$ language sql;

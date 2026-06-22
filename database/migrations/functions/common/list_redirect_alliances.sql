-- Returns active alliances known to the redirector.
create or replace function list_redirect_alliances()
returns table (
    alliance_name text,

    base_legacy_url text
) as $$
    select
        c.name as alliance_name,

        crs.base_legacy_url
    from alliance c
    left join alliance_redirect_settings crs using (alliance_id)
    where c.active = true
    order by c.name;
$$ language sql stable;

-- Returns active communities known to the redirector.
create or replace function list_redirect_communities()
returns table (
    community_name text,

    base_legacy_url text
) as $$
    select
        c.name as community_name,

        crs.base_legacy_url
    from community c
    left join community_redirect_settings crs using (community_id)
    where c.active = true
    order by c.name;
$$ language sql stable;

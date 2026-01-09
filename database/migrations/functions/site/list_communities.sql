-- Returns a list of all active communities.
create or replace function list_communities()
returns json as $$
    select coalesce(json_agg(json_build_object(
        'community_id', community_id,
        'display_name', display_name,
        'logo_url', logo_url,
        'name', name
    ) order by display_name), '[]')
    from community
    where active = true;
$$ language sql;

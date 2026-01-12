-- Returns a list of all active communities.
create or replace function list_communities()
returns json as $$
    select coalesce(json_agg(
        get_community_summary(community_id) order by display_name
    ), '[]')
    from community
    where active = true;
$$ language sql;

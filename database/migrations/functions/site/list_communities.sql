-- Returns all active communities with at least one publicly visible group.
create or replace function list_communities()
returns json as $$
    select coalesce(json_agg(
        get_community_summary(community_id) order by display_name
    ), '[]')
    from community c
    where c.active = true
    and community_has_public_group(c.community_id);
$$ language sql stable;

-- Returns the groups recently added to the community.
create or replace function get_community_recently_added_groups(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_group_summary(p_community_id, g.group_id)
        order by g.created_at desc, g.group_id asc
    ), '[]')
    from (
        select g.created_at, g.group_id
        from "group" g
        where g.community_id = p_community_id
        and is_group_public(g)
        order by g.created_at desc, g.group_id asc
        limit 8
    ) g;
$$ language sql stable;

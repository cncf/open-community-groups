-- Returns the groups recently added to the site.
create or replace function get_site_recently_added_groups()
returns json as $$
    select coalesce(json_agg(
        get_group_summary(g.community_id, g.group_id)
        order by g.created_at desc, g.group_id asc
    ), '[]')
    from (
        select g.community_id, g.created_at, g.group_id
        from "group" g
        join community c on c.community_id = g.community_id
        where c.active = true
        and is_group_public(g)
        order by g.created_at desc, g.group_id asc
        limit 8
    ) g;
$$ language sql stable;

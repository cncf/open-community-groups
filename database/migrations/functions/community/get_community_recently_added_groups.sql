-- Returns the groups recently added to the community.
create or replace function get_community_recently_added_groups(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_group_summary(p_community_id, g.group_id)
    ), '[]')
    from (
        select g.group_id
        from "group" g
        where g.community_id = p_community_id
        and g.active = true
        and g.logo_url is not null
        order by g.created_at desc
        limit 8
    ) g;
$$ language sql;

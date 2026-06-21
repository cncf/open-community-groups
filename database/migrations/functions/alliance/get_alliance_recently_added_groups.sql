-- Returns the groups recently added to the alliance.
create or replace function get_alliance_recently_added_groups(p_alliance_id uuid)
returns json as $$
    select coalesce(json_agg(
        get_group_summary(p_alliance_id, g.group_id)
    ), '[]')
    from (
        select g.group_id
        from "group" g
        where g.alliance_id = p_alliance_id
        and g.active = true
        order by g.created_at desc
        limit 8
    ) g;
$$ language sql;

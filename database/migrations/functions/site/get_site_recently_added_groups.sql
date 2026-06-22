-- Returns the groups recently added to the site.
create or replace function get_site_recently_added_groups()
returns json as $$
    select coalesce(json_agg(
        get_group_summary(g.alliance_id, g.group_id)
    ), '[]')
    from (
        select g.alliance_id, g.group_id
        from "group" g
        join alliance c on c.alliance_id = g.alliance_id
        where c.active = true
        and g.active = true
        order by g.created_at desc
        limit 8
    ) g;
$$ language sql;

-- Returns the groups recently added to the site.
create or replace function get_site_recently_added_groups()
returns json as $$
    select coalesce(json_agg(
        get_group_summary(g.community_id, g.group_id)
    ), '[]')
    from (
        select g.community_id, g.group_id
        from "group" g
        where g.active = true
        and g.logo_url is not null
        order by g.created_at desc
        limit 8
    ) g;
$$ language sql;

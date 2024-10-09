-- Returns the community's recently added groups.
create or replace function get_community_recently_added_groups(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'city', city,
        'country', country,
        'icon_url', icon_url,
        'name', name,
        'region_name', region_name,
        'slug', slug,
        'state', state
    )), '[]')
    from (
        select
            g.city,
            g.country,
            g.icon_url,
            g.name,
            r.name as region_name,
            g.slug,
            g.state
        from "group" g
        join region r using (region_id)
        where g.community_id = p_community_id
        order by g.created_at desc
        limit 9
    ) groups;
$$ language sql;

-- Returns the groups recently added to the community.
create or replace function get_community_recently_added_groups(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'category_name', category_name,
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
            g.slug,
            g.state,
            c.name as category_name,
            r.name as region_name
        from "group" g
        join category c using (category_id)
        left join region r using (region_id)
        where g.community_id = p_community_id
        order by g.created_at desc
        limit 9
    ) groups;
$$ language sql;

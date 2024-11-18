-- Returns the groups recently added to the community.
create or replace function get_community_recently_added_groups(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'category_name', category_name,
        'city', city,
        'country_code', country_code,
        'country_name', country_name,
        'created_at', floor(extract(epoch from created_at)),
        'logo_url', logo_url,
        'name', name,
        'region_name', region_name,
        'slug', slug,
        'state', state
    )), '[]')
    from (
        select
            g.city,
            g.country_code,
            g.country_name,
            g.created_at,
            g.logo_url,
            g.name,
            g.slug,
            g.state,
            gc.name as category_name,
            r.name as region_name
        from "group" g
        join group_category gc using (group_category_id)
        left join region r using (region_id)
        where g.community_id = p_community_id
        and g.active = true
        order by g.created_at desc
        limit 12
    ) groups;
$$ language sql;

-- Returns the community groups that match the filters provided.
create or replace function search_community_groups(p_community_id uuid)
returns json as $$
    select coalesce(json_agg(json_build_object(
        'city', city,
        'country', country,
        'description', description,
        'icon_url', icon_url,
        'name', name,
        'region_name', region_name,
        'slug', slug,
        'state', state
    )), '[]') as json_data
    from (
        select
            g.city,
            g.country,
            g.description,
            g.icon_url,
            g.name,
            g.slug,
            g.state,
            r.name as region_name
        from "group" g
        join region r using (region_id)
        where g.community_id = $1
        order by g.created_at desc
    ) groups;
$$ language sql;

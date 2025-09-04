-- Returns detailed information about a group by its ID.
create or replace function get_group_detailed(p_group_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'active', g.active,
        'category', json_build_object(
            'group_category_id', gc.group_category_id,
            'name', gc.name,
            'normalized_name', gc.normalized_name,
            'order', gc.order
        ),
        'created_at', floor(extract(epoch from g.created_at)),
        'group_id', g.group_id,
        'name', g.name,
        'slug', g.slug,

        'city', g.city,
        'country_code', g.country_code,
        'country_name', g.country_name,
        'description_short', g.description_short,
        'latitude', st_y(g.location::geometry),
        'logo_url', g.logo_url,
        'longitude', st_x(g.location::geometry),
        'region', case when r.region_id is not null then
            json_build_object(
                'region_id', r.region_id,
                'name', r.name,
                'normalized_name', r.normalized_name,
                'order', r.order
            )
        else null end,
        'state', g.state
    )) as json_data
    from "group" g
    join group_category gc using (group_category_id)
    left join region r using (region_id)
    where g.group_id = p_group_id;
$$ language sql;

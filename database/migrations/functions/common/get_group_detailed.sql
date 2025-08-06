-- Returns detailed information about a group by its ID.
create or replace function get_group_detailed(p_group_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'category_name', gc.name,
        'created_at', floor(extract(epoch from g.created_at)),
        'name', g.name,
        'slug', g.slug,

        'city', g.city,
        'country_code', g.country_code,
        'country_name', g.country_name,
        'description', g.description,
        'latitude', st_y(g.location::geometry),
        'logo_url', g.logo_url,
        'longitude', st_x(g.location::geometry),
        'region_name', r.name,
        'state', g.state
    )) as json_data
    from "group" g
    join group_category gc using (group_category_id)
    left join region r using (region_id)
    where g.group_id = p_group_id
    and g.active = true;
$$ language sql;

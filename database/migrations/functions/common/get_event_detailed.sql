-- Returns detailed information about an event by its ID.
create or replace function get_event_detailed(p_event_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'canceled', e.canceled,
        'group_category_name', gc.name,
        'group_name', g.name,
        'group_slug', g.slug,
        'kind', e.event_kind_id,
        'name', e.name,
        'slug', e.slug,
        'timezone', e.timezone,

        'description_short', e.description_short,
        'ends_at', floor(extract(epoch from e.ends_at)),
        'group_city', g.city,
        'group_country_code', g.country_code,
        'group_country_name', g.country_name,
        'group_state', g.state,
        'latitude', st_y(g.location::geometry),
        'logo_url', e.logo_url,
        'longitude', st_x(g.location::geometry),
        'starts_at', floor(extract(epoch from e.starts_at)),
        'venue_address', e.venue_address,
        'venue_city', e.venue_city,
        'venue_name', e.venue_name
    )) as json_data
    from event e
    join "group" g using (group_id)
    join group_category gc on g.group_category_id = gc.group_category_id
    where e.event_id = p_event_id
    and g.active = true
    and e.published = true;
$$ language sql;

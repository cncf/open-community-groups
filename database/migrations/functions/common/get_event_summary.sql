-- Returns summary information about an event by its ID.
create or replace function get_event_summary(p_event_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'canceled', e.canceled,
        'event_id', e.event_id,
        'group_name', g.name,
        'group_slug', g.slug,
        'kind', e.event_kind_id,
        'name', e.name,
        'slug', e.slug,
        'timezone', e.timezone,
        
        'group_city', g.city,
        'group_country_code', g.country_code,
        'group_country_name', g.country_name,
        'group_state', g.state,
        'logo_url', e.logo_url,
        'starts_at', floor(extract(epoch from e.starts_at)),
        'venue_city', e.venue_city
    )) as json_data
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id;
$$ language sql;
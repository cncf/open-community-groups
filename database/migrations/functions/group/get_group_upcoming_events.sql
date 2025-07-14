-- Returns upcoming events for a specific group.
create or replace function get_group_upcoming_events(
    p_community_id uuid,
    p_group_slug text,
    p_event_kind_ids text[],
    p_limit int
) returns json as $$
    select coalesce(json_agg(json_build_object(
        'group_city', group_city,
        'group_country_code', country_code,
        'group_country_name', country_name,
        'group_name', group_name,
        'group_slug', group_slug,
        'group_state', group_state,
        'kind', event_kind_id,
        'logo_url', coalesce(logo_url, group_logo_url),
        'name', name,
        'slug', slug,
        'starts_at', floor(extract(epoch from starts_at)),
        'timezone', timezone,
        'venue_city', venue_city
    )), '[]')
    from (
        select
            e.event_kind_id,
            e.logo_url,
            e.name,
            e.slug,
            e.starts_at,
            e.timezone,
            e.venue_city,
            g.city as group_city,
            g.country_code,
            g.country_name,
            g.logo_url as group_logo_url,
            g.name as group_name,
            g.slug as group_slug,
            g.state as group_state
        from event e
        join "group" g using (group_id)
        where g.community_id = p_community_id
        and g.slug = p_group_slug
        and g.active = true
        and e.published = true
        and e.event_kind_id = any(p_event_kind_ids)
        and e.starts_at is not null
        and e.starts_at > now()
        and e.canceled = false
        order by e.starts_at asc
        limit p_limit
    ) events;
$$ language sql;

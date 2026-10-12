-- Returns the minimal projection of the events matching the filters provided
-- for the explore map and calendar, capped at the limit provided, with the
-- uncapped total. In map view only events with their own location inside the
-- bbox are eligible, and the returned bbox bounds their locations.
create or replace function search_events_minimal(p_filters jsonb, p_limit int)
returns json as $$
    with eligible as (
        select m.*
        from search_events_matches(p_filters) m
        where p_filters->>'view_mode' is distinct from 'map'
        or (
            m.location is not null
            and (
                search_bbox_envelope(p_filters) is null
                or st_intersects(m.location, search_bbox_envelope(p_filters))
            )
        )
    ),
    -- Summarize every eligible event before the cap
    stats as (
        select
            count(*)::bigint as total,
            case
                when p_filters->>'view_mode' = 'map' then
                    search_bbox_json(st_envelope(st_union(st_envelope(location::geometry))))
            end as bbox
        from eligible
    ),
    -- Keep the first events by start date up to the cap
    page as (
        select
            event_id,
            starts_at
        from eligible
        order by starts_at, event_id
        limit p_limit
    )
    -- Build the response payload
    select json_build_object(
        'events', (
            select coalesce(json_agg(
                json_strip_nulls(json_build_object(
                    'community_name', c.name,
                    'event_id', e.event_id,
                    'group_slug', g.slug,
                    'name', e.name,
                    'slug', e.slug,

                    'ends_at', epoch_seconds(e.ends_at),
                    'group_slug_pretty', g.slug_pretty,
                    'latitude', st_y(e.location::geometry),
                    'longitude', st_x(e.location::geometry),
                    'starts_at', epoch_seconds(e.starts_at)
                ))
                order by p.starts_at, p.event_id
            ), '[]'::json)
            from page p
            join event e on e.event_id = p.event_id
            join "group" g on g.group_id = e.group_id
            join community c on c.community_id = g.community_id
        ),
        'total', s.total,

        'bbox', s.bbox,

        'truncated', s.total > p_limit
    )
    from stats s;
$$ language sql;

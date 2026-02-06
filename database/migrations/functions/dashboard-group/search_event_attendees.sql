-- Returns paginated attendees for a group's event using provided filters.
create or replace function search_event_attendees(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse filters for event scope and pagination
        filters as (
            select
                (p_filters->>'event_id')::uuid as event_id,
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        -- Select the paginated attendee list
        attendees as (
            select
                ea.checked_in,
                extract(epoch from ea.created_at)::bigint as created_at,
                u.user_id,
                u.username,

                extract(epoch from ea.checked_in_at)::bigint as checked_in_at,
                u.company,
                u.name,
                u.photo_url,
                u.title
            from event_attendee ea
            join event e on e.event_id = ea.event_id
            join "user" u on u.user_id = ea.user_id
            where e.group_id = p_group_id
            and ea.event_id = (select event_id from filters)
            order by coalesce(lower(u.name), lower(u.username)) asc, u.user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count total attendees before pagination
        totals as (
            select count(*)::int as total
            from event_attendee ea
            join event e on e.event_id = ea.event_id
            where e.group_id = p_group_id
            and ea.event_id = (select event_id from filters)
        ),
        -- Render attendees as JSON
        attendees_json as (
            select coalesce(json_agg(row_to_json(attendees)), '[]'::json) as attendees
            from attendees
        )
    -- Build final payload
    select json_build_object(
        'attendees', attendees_json.attendees,
        'total', totals.total
    )
    from attendees_json, totals;
$$ language sql;

-- Returns attendees for a group's event using provided filters.
create or replace function search_event_attendees(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        filters as (
            select (p_filters->>'event_id')::uuid as event_id
        ),
        attendees as (
            select
                ea.checked_in,
                extract(epoch from ea.created_at)::bigint as created_at,
                u.username,

                u.name,
                u.photo_url
            from event_attendee ea
            join event e on e.event_id = ea.event_id
            join "user" u on u.user_id = ea.user_id
            where e.group_id = p_group_id
            and ea.event_id = (select event_id from filters)
            order by coalesce(lower(u.name), lower(u.username)) asc
        )
    select coalesce(json_agg(row_to_json(attendees)), '[]'::json)
    from attendees;
$$ language sql;


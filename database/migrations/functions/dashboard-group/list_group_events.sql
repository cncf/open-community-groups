-- Returns all events for a group for dashboard administration.
create or replace function list_group_events(p_group_id uuid)
returns json as $$
    with group_events as (
        select e.event_id, e.name, e.starts_at
        from event e
        where e.group_id = p_group_id
        and e.deleted = false
    )
    select json_build_object(
        'past', coalesce((
            select json_agg(get_event_summary(ge.event_id) order by ge.starts_at desc nulls last, ge.name asc)
            from group_events ge
            where ge.starts_at is not null
            and ge.starts_at < current_timestamp
        ), '[]'::json),
        'upcoming', coalesce((
            select json_agg(get_event_summary(ge.event_id) order by ge.starts_at asc nulls last, ge.name asc)
            from group_events ge
            where ge.starts_at is null
            or ge.starts_at >= current_timestamp
        ), '[]'::json)
    );
$$ language sql;

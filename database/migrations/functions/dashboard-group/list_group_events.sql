-- Returns paginated events for a group for dashboard administration.
create or replace function list_group_events(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'past_offset')::int as past_offset,
                (p_filters->>'upcoming_offset')::int as upcoming_offset
        ),
        group_events as (
            select e.event_id, e.name, e.starts_at, e.group_id, g.community_id
            from event e
            join "group" g using (group_id)
            where e.group_id = p_group_id
            and e.deleted = false
        ),
        past_events as (
            select ge.*
            from group_events ge
            where ge.starts_at is not null
            and ge.starts_at < current_timestamp
            order by ge.starts_at desc nulls last, ge.name asc, ge.event_id asc
            offset (select past_offset from filters)
            limit (select limit_value from filters)
        ),
        past_total as (
            select count(*)::int as total
            from group_events ge
            where ge.starts_at is not null
            and ge.starts_at < current_timestamp
        ),
        upcoming_events as (
            select ge.*
            from group_events ge
            where ge.starts_at is null
            or ge.starts_at >= current_timestamp
            order by ge.starts_at asc nulls last, ge.name asc, ge.event_id asc
            offset (select upcoming_offset from filters)
            limit (select limit_value from filters)
        ),
        upcoming_total as (
            select count(*)::int as total
            from group_events ge
            where ge.starts_at is null
            or ge.starts_at >= current_timestamp
        ),
        past_json as (
            select coalesce(
                json_agg(
                    get_event_summary(past_events.community_id, past_events.group_id, past_events.event_id)
                    order by past_events.starts_at desc nulls last, past_events.name asc, past_events.event_id asc
                ),
                '[]'::json
            ) as events
            from past_events
        ),
        upcoming_json as (
            select coalesce(
                json_agg(
                    get_event_summary(
                        upcoming_events.community_id,
                        upcoming_events.group_id,
                        upcoming_events.event_id
                    )
                    order by upcoming_events.starts_at asc nulls last, upcoming_events.name asc, upcoming_events.event_id asc
                ),
                '[]'::json
            ) as events
            from upcoming_events
        )
    select json_build_object(
        'past', json_build_object(
            'events', past_json.events,
            'total', past_total.total
        ),
        'upcoming', json_build_object(
            'events', upcoming_json.events,
            'total', upcoming_total.total
        )
    )
    from past_json, past_total, upcoming_json, upcoming_total;
$$ language sql;

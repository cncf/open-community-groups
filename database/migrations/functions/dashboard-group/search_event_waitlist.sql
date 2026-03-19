-- Returns paginated waitlist entries for a group's event using provided filters.
create or replace function search_event_waitlist(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse filters for event scope and pagination
        filters as (
            select
                (p_filters->>'event_id')::uuid as event_id,
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        -- Select the paginated waitlist entries
        waitlist as (
            select
                extract(epoch from ew.created_at)::bigint as created_at,
                u.user_id,
                u.username,

                u.company,
                u.name,
                u.photo_url,
                u.title
            from event_waitlist ew
            join event e on e.event_id = ew.event_id
            join "user" u on u.user_id = ew.user_id
            where e.group_id = p_group_id
            and ew.event_id = (select event_id from filters)
            order by ew.created_at asc, ew.user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count total waitlist entries before pagination
        totals as (
            select count(*)::int as total
            from event_waitlist ew
            join event e on e.event_id = ew.event_id
            where e.group_id = p_group_id
            and ew.event_id = (select event_id from filters)
        ),
        -- Render waitlist entries as JSON
        waitlist_json as (
            select coalesce(json_agg(row_to_json(waitlist)), '[]'::json) as waitlist
            from waitlist
        )
    -- Build final payload
    select json_build_object(
        'total', totals.total,
        'waitlist', waitlist_json.waitlist
    )
    from waitlist_json, totals;
$$ language sql;

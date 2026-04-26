-- Returns paginated invitation requests for a group's event using provided filters.
create or replace function search_event_invitation_requests(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse filters for event scope and pagination
        filters as (
            select
                (p_filters->>'event_id')::uuid as event_id,
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        -- Select the paginated invitation requests
        invitation_requests as (
            select
                extract(epoch from eir.created_at)::bigint as created_at,
                eir.status as invitation_request_status,
                u.user_id,
                u.username,

                u.company,
                u.name,
                u.photo_url,
                extract(epoch from eir.reviewed_at)::bigint as reviewed_at,
                u.title
            from event_invitation_request eir
            join event e on e.event_id = eir.event_id
            join "user" u on u.user_id = eir.user_id
            where e.group_id = p_group_id
            and eir.event_id = (select event_id from filters)
            order by
                case eir.status
                    when 'pending' then 0
                    when 'accepted' then 1
                    else 2
                end asc,
                eir.created_at asc,
                eir.user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count total invitation requests before pagination
        totals as (
            select count(*)::int as total
            from event_invitation_request eir
            join event e on e.event_id = eir.event_id
            where e.group_id = p_group_id
            and eir.event_id = (select event_id from filters)
        ),
        -- Render invitation requests as JSON
        invitation_requests_json as (
            select coalesce(
                json_agg(row_to_json(invitation_requests)),
                '[]'::json
            ) as invitation_requests
            from invitation_requests
        )
    -- Build final payload
    select json_build_object(
        'invitation_requests', invitation_requests_json.invitation_requests,
        'total', totals.total
    )
    from invitation_requests_json, totals;
$$ language sql;

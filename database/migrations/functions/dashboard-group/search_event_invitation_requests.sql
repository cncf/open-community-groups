-- Returns paginated invitation requests for a group's event using provided filters.
create or replace function search_event_invitation_requests(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse filters for event scope and pagination
        filters as (
            select
                (p_filters->>'event_id')::uuid as event_id,
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value,
                nullif(btrim(p_filters->>'ts_query'), '') as ts_query_value
        ),
        -- Prepare text search with prefix matching
        search_filter as (
            select
                ts_rewrite(
                    websearch_to_tsquery('simple', ts_query_value),
                    format('
                        select
                            to_tsquery(''simple'', lexeme),
                            to_tsquery(''simple'', lexeme || '':*'')
                        from unnest(tsvector_to_array(to_tsvector(''simple'', %L))) as lexeme
                        ', ts_query_value
                    )
                ) as ts_query
            from filters
            where ts_query_value is not null
        ),
        -- Select invitation requests with internal search data
        base_invitation_requests as (
            select
                extract(epoch from eir.created_at)::bigint as created_at,
                eir.created_at as created_at_sort,
                eir.status as invitation_request_status,
                u.user_id,
                u.username,

                u.company,
                u.name,
                u.photo_url,
                extract(epoch from eir.reviewed_at)::bigint as reviewed_at,
                u.tsdoc,
                u.title
            from event_invitation_request eir
            join event e on e.event_id = eir.event_id
            join "user" u on u.user_id = eir.user_id
            where e.group_id = p_group_id
            and eir.event_id = (select event_id from filters)
        ),
        -- Apply table filters while retaining internal search data
        filtered_invitation_requests as (
            select *
            from base_invitation_requests
            where (
                not exists (select 1 from search_filter)
                or exists (
                    select 1
                    from search_filter
                    where search_filter.ts_query @@ base_invitation_requests.tsdoc
                )
            )
        ),
        -- Apply pagination and project public invitation request fields
        invitation_requests as (
            select
                created_at,
                invitation_request_status,
                user_id,
                username,

                company,
                name,
                photo_url,
                reviewed_at,
                title
            from filtered_invitation_requests
            order by
                case invitation_request_status
                    when 'pending' then 0
                    when 'accepted' then 1
                    else 2
                end asc,
                created_at_sort asc,
                user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count filtered invitation requests before pagination
        totals as (
            select count(*)::int as total
            from filtered_invitation_requests
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

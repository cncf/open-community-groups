-- Returns paginated waitlist entries for a group's event using provided filters.
create or replace function search_event_waitlist(p_group_id uuid, p_filters jsonb)
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
        -- Select waitlist entries with internal search data
        base_waitlist as (
            select
                extract(epoch from ew.created_at)::bigint as created_at,
                ew.created_at as created_at_sort,
                u.user_id,
                u.username,
                row_number() over (order by ew.created_at asc, ew.user_id asc)::int as waitlist_position,

                u.company,
                u.name,
                u.photo_url,
                u.tsdoc,
                u.title
            from event_waitlist ew
            join event e on e.event_id = ew.event_id
            join "user" u on u.user_id = ew.user_id
            where e.group_id = p_group_id
            and ew.event_id = (select event_id from filters)
        ),
        -- Apply table filters while retaining internal search data
        filtered_waitlist as (
            select *
            from base_waitlist
            where (
                not exists (select 1 from search_filter)
                or exists (
                    select 1
                    from search_filter
                    where search_filter.ts_query @@ base_waitlist.tsdoc
                )
            )
        ),
        -- Apply pagination and project public waitlist fields
        waitlist as (
            select
                created_at,
                user_id,
                username,
                waitlist_position,

                company,
                name,
                photo_url,
                title
            from filtered_waitlist
            order by created_at_sort asc, user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count filtered waitlist entries before pagination
        totals as (
            select count(*)::int as total
            from filtered_waitlist
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

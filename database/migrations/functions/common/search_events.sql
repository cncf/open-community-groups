-- Returns a page of the events that match the filters provided, with the total.
-- Uses PL/pgSQL with `force_custom_plan` so each call is planned with the
-- actual pagination values.
create or replace function search_events(p_filters jsonb)
returns json as $$
declare
    v_filters record;
    v_sort_by text := coalesce(p_filters->>'sort_by', 'date');
    v_sort_direction text := case lower(coalesce(p_filters->>'sort_direction', 'asc'))
        when 'desc' then 'desc'
        else 'asc'
    end;
begin
    -- Prepare pagination filters
    select *
    into v_filters
    from parse_search_filters(p_filters);

    -- Match, paginate and aggregate events
    return (
    with matches as (
        select *
        from search_events_matches(p_filters)
    ),
    -- Keep the requested page with the selected sort strategy and number it;
    -- limiting before numbering lets the planner keep only the top rows instead
    -- of sorting every match, so keep both order lists identical
    page as (
        select
            community_id,
            event_id,
            group_id,
            row_number() over (
                order by
                    (case when v_sort_by = 'date' and v_sort_direction = 'asc' then starts_at end) asc,
                    (case when v_sort_by = 'date' and v_sort_direction = 'desc' then starts_at end) desc,
                    (case when v_sort_by = 'distance' and v_sort_direction = 'asc' then distance end) asc,
                    (case when v_sort_by = 'distance' and v_sort_direction = 'desc' then distance end) desc,
                    starts_at asc,
                    event_id asc
            ) as ordinal
        from (
            select
                community_id,
                distance,
                event_id,
                group_id,
                starts_at
            from matches
            order by
                (case when v_sort_by = 'date' and v_sort_direction = 'asc' then starts_at end) asc,
                (case when v_sort_by = 'date' and v_sort_direction = 'desc' then starts_at end) desc,
                (case when v_sort_by = 'distance' and v_sort_direction = 'asc' then distance end) asc,
                (case when v_sort_by = 'distance' and v_sort_direction = 'desc' then distance end) desc,
                starts_at asc,
                event_id asc
            limit v_filters.limit_value
            offset v_filters.offset_value
        ) as page_matches
    )
    -- Build response payload with total count
    select json_build_object(
        'events',
        (
            -- Render paginated events as summaries in page order
            select coalesce(json_agg(
                get_event_summary(community_id, group_id, event_id)
                order by ordinal
            ), '[]'::json)
            from page
        ),
        'total',
        (
            -- Count total events before pagination
            select count(*)::bigint from matches
        )
    )
    );
end
$$ language plpgsql set plan_cache_mode = force_custom_plan;

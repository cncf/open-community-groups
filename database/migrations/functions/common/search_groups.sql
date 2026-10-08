-- Returns a page of the groups that match the filters provided, with the total.
-- Uses PL/pgSQL with `force_custom_plan` so each call is planned with the
-- actual pagination values.
create or replace function search_groups(p_filters jsonb)
returns json as $$
declare
    v_filters record;
    v_sort_by text := coalesce(p_filters->>'sort_by', 'name');
begin
    -- Prepare pagination filters
    select *
    into v_filters
    from parse_search_filters(p_filters);

    -- Match, paginate and aggregate groups
    return (
    with matches as (
        select *
        from search_groups_matches(p_filters)
    ),
    -- Keep the requested page with the selected sort strategy and number it;
    -- limiting before numbering lets the planner keep only the top rows instead
    -- of sorting every match, so keep both order lists identical
    page as (
        select
            community_id,
            group_id,
            row_number() over (
                order by
                    (case when v_sort_by = 'date' then created_at end) desc,
                    (case when v_sort_by = 'distance' then distance end) asc,
                    (case when v_sort_by = 'name' then name end) asc,
                    created_at desc,
                    group_id asc
            ) as ordinal
        from (
            select
                community_id,
                created_at,
                distance,
                group_id,
                name
            from matches
            order by
                (case when v_sort_by = 'date' then created_at end) desc,
                (case when v_sort_by = 'distance' then distance end) asc,
                (case when v_sort_by = 'name' then name end) asc,
                created_at desc,
                group_id asc
            limit v_filters.limit_value
            offset v_filters.offset_value
        ) as page_matches
    )
    -- Build response payload with total count
    select json_build_object(
        'groups',
        (
            -- Render paginated groups as summaries in page order
            select coalesce(json_agg(
                get_group_summary(community_id, group_id)
                order by ordinal
            ), '[]'::json)
            from page
        ),
        'total',
        (
            -- Count total groups before pagination
            select count(*)::bigint from matches
        )
    )
    );
end
$$ language plpgsql set plan_cache_mode = force_custom_plan;

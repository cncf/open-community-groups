-- Lists searchable badge definitions for a group.
create or replace function list_badges(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Normalize pagination and search filters
        filters as (
            select
                greatest(coalesce((p_filters->>'limit')::integer, 20), 1) as limit_value,
                greatest(coalesce((p_filters->>'offset')::integer, 0), 0) as offset_value,
                nullif(btrim(p_filters->>'query'), '') as query_value
        ),
        -- Apply group ownership and full-text search
        filtered as (
            select b.*
            from badge b
            cross join filters f
            where b.group_id = p_group_id
            and (
                f.query_value is null
                or b.tsdoc @@ websearch_to_tsquery('simple', f.query_value)
                or b.name ilike '%' || escape_ilike_pattern(f.query_value) || '%'
            )
        ),
        -- Select the requested page in stable name order
        page as (
            select *
            from filtered
            order by lower(name), badge_id
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        )
    -- Return badge rows and the unpaginated total
    select json_build_object(
        'badges', coalesce(
            (
                select json_agg(
                    json_build_object(
                        'badge_id', badge_id,
                        'criteria', criteria,
                        'description', description,
                        'image_file_name', image_file_name,
                        'name', name
                    )
                    order by lower(name), badge_id
                )
                from page
            ),
            '[]'::json
        ),
        'total', (select count(*)::integer from filtered)
    );
$$ language sql;

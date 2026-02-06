-- Returns sponsors for a given group, optionally unpaginated.
create or replace function list_group_sponsors(p_group_id uuid, p_filters jsonb, p_full_list boolean)
returns json as $$
    with
        -- Parse pagination filters
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        -- Select sponsors with optional full-list mode
        sponsors as (
            select
                gs.group_sponsor_id,
                gs.logo_url,
                gs.name,

                gs.website_url
            from group_sponsor gs
            where gs.group_id = p_group_id
            order by gs.name asc, gs.group_sponsor_id asc
            offset case when p_full_list then 0 else (select offset_value from filters) end
            limit case when p_full_list then null else (select limit_value from filters) end
        ),
        -- Count all sponsors before pagination
        totals as (
            select count(*)::int as total
            from group_sponsor gs
            where gs.group_id = p_group_id
        ),
        -- Render sponsors as JSON
        sponsors_json as (
            select coalesce(
                json_agg(
                    json_strip_nulls(row_to_json(sponsors))
                    order by sponsors.name asc, sponsors.group_sponsor_id asc
                ), '[]'::json
            ) as sponsors
            from sponsors
        )
    -- Build final payload
    select json_build_object(
        'sponsors', sponsors_json.sponsors,
        'total', totals.total
    )
    from totals, sponsors_json;
$$ language sql;

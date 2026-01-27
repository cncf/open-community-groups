-- Returns paginated sponsors for a given group.
create or replace function list_group_sponsors(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        filters as (
            select
                coalesce((p_filters->>'limit')::int, 50) as limit_value,
                coalesce((p_filters->>'offset')::int, 0) as offset_value
        ),
        sponsors as (
            select
                gs.group_sponsor_id,
                gs.logo_url,
                gs.name,

                gs.website_url
            from group_sponsor gs
            where gs.group_id = p_group_id
            order by gs.name asc, gs.group_sponsor_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        totals as (
            select count(*)::int as total
            from group_sponsor gs
            where gs.group_id = p_group_id
        ),
        sponsors_json as (
            select coalesce(
                json_agg(
                    json_strip_nulls(row_to_json(sponsors))
                    order by sponsors.name asc, sponsors.group_sponsor_id asc
                ), '[]'::json
            ) as sponsors
            from sponsors
        )
    select json_build_object(
        'sponsors', sponsors_json.sponsors,
        'total', totals.total
    )
    from totals, sponsors_json;
$$ language sql;

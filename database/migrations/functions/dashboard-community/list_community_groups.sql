-- Returns a page of the community groups for the dashboard, including inactive
-- groups and groups of inactive communities, with the total. Deleted groups
-- are excluded.
create or replace function list_community_groups(p_community_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination and text search filters
        filters as (
            select
                f.limit_value,
                f.offset_value,
                f.tsquery
            from parse_search_filters(p_filters) f
        ),
        -- Select the community groups matching the text search query
        matches as (
            select
                g.created_at,
                g.group_id,
                g.name
            from "group" g
            cross join filters f
            where g.community_id = p_community_id
            and g.deleted = false
            and (
                f.tsquery is null
                or f.tsquery @@ g.tsdoc
            )
        ),
        -- Keep the requested page sorted by name
        page as (
            select
                m.group_id,
                row_number() over (
                    order by m.name asc, m.created_at desc, m.group_id asc
                ) as ordinal
            from (
                select
                    created_at,
                    group_id,
                    name
                from matches
                order by name asc, created_at desc, group_id asc
                offset (select offset_value from filters)
                limit (select limit_value from filters)
            ) as m
        )
    -- Build the response payload with the total before pagination
    select json_build_object(
        'groups', (
            select coalesce(json_agg(
                get_group_summary(p_community_id, group_id)
                order by ordinal
            ), '[]'::json)
            from page
        ),
        'total', (
            select count(*)::bigint
            from matches
        )
    );
$$ language sql;

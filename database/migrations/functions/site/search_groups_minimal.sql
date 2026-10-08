-- Returns the minimal projection of the located groups matching the filters
-- provided for the explore map, capped at the limit provided, with the
-- uncapped total and the bbox of every eligible group.
create or replace function search_groups_minimal(p_filters jsonb, p_limit int)
returns json as $$
    with eligible as (
        select m.*
        from search_groups_matches(p_filters) m
        where m.location is not null
    ),
    -- Summarize every eligible group before the cap
    stats as (
        select
            count(*)::bigint as total,
            search_bbox_json(st_envelope(st_union(st_envelope(location::geometry)))) as bbox
        from eligible
    ),
    -- Keep the first groups by name up to the cap
    page as (
        select
            group_id,
            name
        from eligible
        order by name, group_id
        limit p_limit
    )
    -- Build the response payload
    select json_build_object(
        'groups', (
            select coalesce(json_agg(
                json_strip_nulls(json_build_object(
                    'active', g.active,
                    'community_name', c.name,
                    'group_id', g.group_id,
                    'name', g.name,
                    'slug', g.slug,

                    'latitude', st_y(g.location::geometry),
                    'longitude', st_x(g.location::geometry),
                    'slug_pretty', g.slug_pretty
                ))
                order by p.name, p.group_id
            ), '[]'::json)
            from page p
            join "group" g on g.group_id = p.group_id
            join community c on c.community_id = g.community_id
        ),
        'total', s.total,

        'bbox', s.bbox,

        'truncated', s.total > p_limit
    )
    from stats s;
$$ language sql;

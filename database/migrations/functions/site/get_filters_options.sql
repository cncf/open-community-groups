-- Returns the filters options used in the explore page. When a community_id is
-- provided, community-specific filters (event_category, group_category, region)
-- are included. When NULL, only the distance filter is returned.
create or replace function get_filters_options(p_community_id uuid default null)
returns json as $$
    select json_strip_nulls(json_build_object(
        'distance', json_build_array(
            json_build_object(
                'name', '10 km',
                'value', '10000'
            ),
            json_build_object(
                'name', '50 km',
                'value', '50000'
            ),
            json_build_object(
                'name', '100 km',
                'value', '100000'
            ),
            json_build_object(
                'name', '500 km',
                'value', '500000'
            ),
            json_build_object(
                'name', '1000 km',
                'value', '1000000'
            )
        ),
        'event_category', case when p_community_id is not null then (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', slug
            )), '[]')
            from (
                select name, slug
                from event_category
                where community_id = p_community_id
                order by "order" asc nulls last
            ) as event_categories
        ) end,
        'group_category', case when p_community_id is not null then (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', normalized_name
            )), '[]')
            from (
                select name, normalized_name
                from group_category
                where community_id = p_community_id
                order by "order" asc nulls last
            ) as group_categories
        ) end,
        'region', case when p_community_id is not null then (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', normalized_name
            )), '[]')
            from (
                select name, normalized_name
                from region
                where community_id = p_community_id
                order by "order" asc nulls last
            ) as regions
        ) end
    ));
$$ language sql;

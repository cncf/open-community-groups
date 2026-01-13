-- Returns the filters options used in the explore page. When a community name
-- is provided, community-specific filters are included.
create or replace function get_filters_options(p_community_name text default null)
returns json as $$
    select json_strip_nulls(json_build_object(
        -- Global filters
        'communities', (
            select coalesce(json_agg(
                get_community_summary(community_id) order by display_name
            ), '[]')
            from community
            where active = true
        ),
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

        -- Community-specific filters
        'event_category', case when p_community_name is not null then (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', slug
            )), '[]')
            from (
                select ec.name, ec.slug
                from event_category ec
                join community c using (community_id)
                where c.name = p_community_name
                order by ec."order" asc nulls last
            ) as event_categories
        ) end,
        'group_category', case when p_community_name is not null then (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', normalized_name
            )), '[]')
            from (
                select gc.name, gc.normalized_name
                from group_category gc
                join community c using (community_id)
                where c.name = p_community_name
                order by gc."order" asc nulls last
            ) as group_categories
        ) end,
        'region', case when p_community_name is not null then (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', normalized_name
            )), '[]')
            from (
                select r.name, r.normalized_name
                from region r
                join community c using (community_id)
                where c.name = p_community_name
                order by r."order" asc nulls last
            ) as regions
        ) end
    ));
$$ language sql;

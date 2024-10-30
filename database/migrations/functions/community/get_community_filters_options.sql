-- Returns the filters options used in the community explore page.
create or replace function get_community_filters_options(p_community_id uuid)
returns json as $$
    select json_build_object(
        'category', (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', normalized_name
            )), '[]')
            from category
            where community_id = p_community_id
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
        'region', (
            select coalesce(json_agg(json_build_object(
                'name', name,
                'value', normalized_name
            )), '[]')
            from region
            where community_id = p_community_id
        )
    );
$$ language sql;

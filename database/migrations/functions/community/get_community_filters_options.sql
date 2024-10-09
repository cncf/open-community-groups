-- Returns the filters options used in the community explore page.
create or replace function get_community_filters_options(p_community_id uuid)
returns json as $$
    select json_build_object(
        'distance', json_build_array(
            json_build_object(
                'name', '2 miles',
                'value', '2 miles'
            ),
            json_build_object(
                'name', '5 miles',
                'value', '5 miles'
            ),
            json_build_object(
                'name', '10 miles',
                'value', '10 miles'
            ),
            json_build_object(
                'name', '25 miles',
                'value', '25 miles'
            ),
            json_build_object(
                'name', '50 miles',
                'value', '50 miles'
            ),
            json_build_object(
                'name', '100 miles',
                'value', '100 miles'
            )
        ),
        'region', (
            select coalesce(json_agg(json_build_object(
                'name', r.name,
                'value', r.normalized_name
            )), '[]')
            from region r
            where community_id = p_community_id
        )
    );
$$ language sql;

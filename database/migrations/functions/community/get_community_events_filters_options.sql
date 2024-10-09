-- Returns the filters options for the community's events.
create or replace function get_community_events_filters_options(p_community_id uuid)
returns json as $$
    select json_build_object(
        'regions', (
            select coalesce(json_agg(json_build_object(
                'name', r.name,
                'value', r.normalized_name
            )), '[]')
            from region r
            where community_id = p_community_id
        )
    );
$$ language sql;

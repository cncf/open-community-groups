-- Returns the information needed to render the community explore page.
create or replace function get_community_explore_data(p_community_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'community', (select get_community_data(p_community_id))
    )) as json_data
    from community
    where community_id = p_community_id;
$$ language sql;

-- Returns summary information about a community.
create or replace function get_community_summary(p_community_id uuid)
returns json as $$
    select json_build_object(
        'banner_mobile_url', banner_mobile_url,
        'banner_url', banner_url,
        'community_id', community_id,
        'display_name', display_name,
        'logo_url', logo_url,
        'name', name
    )
    from community
    where community_id = p_community_id;
$$ language sql;

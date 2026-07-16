-- Returns summary information about a alliance.
create or replace function get_alliance_summary(p_alliance_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'banner_mobile_url', banner_mobile_url,
        'banner_url', banner_url,
        'alliance_id', alliance_id,
        'coffee_meet_enabled', coffee_meet_enabled,
        'display_name', display_name,
        'intentional_dating_enabled', intentional_dating_enabled,
        'logo_url', logo_url,
        'mentorship_enabled', mentorship_enabled,
        'mock_interviews_enabled', mock_interviews_enabled,
        'name', name,

        'ad_banner_link_url', ad_banner_link_url,
        'ad_banner_url', ad_banner_url,
        'og_image_url', og_image_url
    ))
    from alliance
    where alliance_id = p_alliance_id;
$$ language sql;

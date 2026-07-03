-- Returns all information about the alliance provided.
create or replace function get_alliance_full(p_alliance_id uuid)
returns json as $$
    -- Build full alliance payload
    select json_strip_nulls(json_build_object(
        -- Include core alliance fields
        'active', active,
        'banner_mobile_url', banner_mobile_url,
        'banner_url', banner_url,
        'alliance_id', alliance_id,
        'alliance_site_layout_id', alliance_site_layout_id,
        'created_at', floor(extract(epoch from created_at)*1000),
        'coffee_meet_enabled', coffee_meet_enabled,
        'description', description,
        'display_name', display_name,
        'group_team_management_restricted', group_team_management_restricted,
        'logo_url', logo_url,
        'mentorship_enabled', mentorship_enabled,
        'name', name,

        -- Include optional alliance profile fields
        'ad_banner_link_url', ad_banner_link_url,
        'ad_banner_url', ad_banner_url,
        'bluesky_url', bluesky_url,
        'extra_links', extra_links,
        'facebook_url', facebook_url,
        'flickr_url', flickr_url,
        'github_url', github_url,
        'instagram_url', instagram_url,
        'linkedin_url', linkedin_url,
        'new_group_details', new_group_details,
        'og_image_url', og_image_url,
        'photos_urls', photos_urls,
        'slack_url', slack_url,
        'twitter_url', twitter_url,
        'website_url', website_url,
        'wechat_url', wechat_url,
        'youtube_url', youtube_url
    )) as json_data
    from alliance
    where alliance_id = p_alliance_id;
$$ language sql;

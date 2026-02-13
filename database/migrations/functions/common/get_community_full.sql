-- Returns all information about the community provided.
create or replace function get_community_full(p_community_id uuid)
returns json as $$
    -- Build full community payload
    select json_strip_nulls(json_build_object(
        -- Include core community fields
        'active', active,
        'banner_mobile_url', banner_mobile_url,
        'banner_url', banner_url,
        'community_id', community_id,
        'community_site_layout_id', community_site_layout_id,
        'created_at', floor(extract(epoch from created_at)*1000),
        'description', description,
        'display_name', display_name,
        'logo_url', logo_url,
        'name', name,

        -- Include optional community profile fields
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
    from community
    where community_id = p_community_id;
$$ language sql;

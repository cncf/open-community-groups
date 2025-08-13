-- Returns all information about the community provided.
create or replace function get_community(p_community_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'active', active,
        'ad_banner_link_url', ad_banner_link_url,
        'ad_banner_url', ad_banner_url,
        'community_id', community_id,
        'community_site_layout_id', community_site_layout_id,
        'copyright_notice', copyright_notice,
        'created_at', floor(extract(epoch from created_at)*1000),
        'description', description,
        'display_name', display_name,
        'extra_links', extra_links,
        'facebook_url', facebook_url,
        'flickr_url', flickr_url,
        'footer_logo_url', footer_logo_url,
        'github_url', github_url,
        'header_logo_url', header_logo_url,
        'host', host,
        'instagram_url', instagram_url,
        'linkedin_url', linkedin_url,
        'name', name,
        'new_group_details', new_group_details,
        'photos_urls', photos_urls,
        'slack_url', slack_url,
        'theme', theme,
        'title', title,
        'twitter_url', twitter_url,
        'website_url', website_url,
        'wechat_url', wechat_url,
        'youtube_url', youtube_url
    )) as json_data
    from community
    where community_id = p_community_id;
$$ language sql;

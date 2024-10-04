-- Returns some information about the community provided.
create or replace function get_community_data(p_community_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'ad_banner_link_url', ad_banner_link_url,
        'ad_banner_url', ad_banner_url,
        'copyright_notice', copyright_notice,
        'description', description,
        'display_name', display_name,
        'extra_links', extra_links,
        'facebook_url', facebook_url,
        'flickr_url', flickr_url,
        'footer_logo_url', footer_logo_url,
        'github_url', github_url,
        'header_logo_url', header_logo_url,
        'homepage_url', homepage_url,
        'instagram_url', instagram_url,
        'linkedin_url', linkedin_url,
        'new_group_details', new_group_details,
        'photos_urls', photos_urls,
        'regions', (
            select to_json(array_agg(name))
            from region
            where community_id = p_community_id
        ),
        'slack_url', slack_url,
        'title', title,
        'twitter_url', twitter_url,
        'wechat_url', wechat_url,
        'youtube_url', youtube_url
    )) as json_data
    from community
    where community_id = p_community_id;
$$ language sql;

-- Updates a community's settings.
create or replace function update_community(
    p_community_id uuid,
    p_data jsonb
) returns void as $$
    update community
    set
        banner_mobile_url = coalesce(p_data->>'banner_mobile_url', banner_mobile_url),
        banner_url = coalesce(p_data->>'banner_url', banner_url),
        description = coalesce(p_data->>'description', description),
        display_name = coalesce(p_data->>'display_name', display_name),
        logo_url = coalesce(p_data->>'logo_url', logo_url),

        ad_banner_link_url = nullif(p_data->>'ad_banner_link_url', ''),
        ad_banner_url = nullif(p_data->>'ad_banner_url', ''),
        extra_links = nullif(p_data->'extra_links', 'null'::jsonb),
        facebook_url = nullif(p_data->>'facebook_url', ''),
        flickr_url = nullif(p_data->>'flickr_url', ''),
        github_url = nullif(p_data->>'github_url', ''),
        instagram_url = nullif(p_data->>'instagram_url', ''),
        linkedin_url = nullif(p_data->>'linkedin_url', ''),
        new_group_details = nullif(p_data->>'new_group_details', ''),
        photos_urls = case
            when p_data ? 'photos_urls' and jsonb_typeof(p_data->'photos_urls') != 'null' then
                array(select jsonb_array_elements_text(p_data->'photos_urls'))
            else null
        end,
        slack_url = nullif(p_data->>'slack_url', ''),
        twitter_url = nullif(p_data->>'twitter_url', ''),
        website_url = nullif(p_data->>'website_url', ''),
        wechat_url = nullif(p_data->>'wechat_url', ''),
        youtube_url = nullif(p_data->>'youtube_url', '')
    where community_id = p_community_id;
$$ language sql;

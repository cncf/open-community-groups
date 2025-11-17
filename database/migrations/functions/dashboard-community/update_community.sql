-- Updates a community's settings.
create or replace function update_community(
    p_community_id uuid,
    p_data jsonb
) returns void as $$
begin
    update community
    set
        description = coalesce(p_data->>'description', description),
        display_name = coalesce(p_data->>'display_name', display_name),
        header_logo_url = coalesce(p_data->>'header_logo_url', header_logo_url),
        name = coalesce(p_data->>'name', name),
        theme = case when p_data ? 'primary_color' then jsonb_build_object('primary_color', p_data->>'primary_color') else theme end,
        title = coalesce(p_data->>'title', title),
        ad_banner_link_url = nullif(p_data->>'ad_banner_link_url', ''),
        ad_banner_url = nullif(p_data->>'ad_banner_url', ''),
        copyright_notice = nullif(p_data->>'copyright_notice', ''),
        extra_links = nullif(p_data->'extra_links', 'null'::jsonb),
        facebook_url = nullif(p_data->>'facebook_url', ''),
        favicon_url = nullif(p_data->>'favicon_url', ''),
        flickr_url = nullif(p_data->>'flickr_url', ''),
        footer_logo_url = nullif(p_data->>'footer_logo_url', ''),
        github_url = nullif(p_data->>'github_url', ''),
        instagram_url = nullif(p_data->>'instagram_url', ''),
        jumbotron_image_url = nullif(p_data->>'jumbotron_image_url', ''),
        linkedin_url = nullif(p_data->>'linkedin_url', ''),
        new_group_details = nullif(p_data->>'new_group_details', ''),
        og_image_url = nullif(p_data->>'og_image_url', ''),
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
end
$$ language plpgsql;

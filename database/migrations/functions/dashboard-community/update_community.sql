-- Updates a community's settings.
-- Only updates fields that are present in the input JSON.
create or replace function update_community(
    p_community_id uuid,
    p_data jsonb
) returns void as $$
begin
    update community
    set
        active = coalesce((p_data->>'active')::boolean, active),
        community_site_layout_id = coalesce(p_data->>'community_site_layout_id', community_site_layout_id),
        description = coalesce(p_data->>'description', description),
        display_name = coalesce(p_data->>'display_name', display_name),
        header_logo_url = coalesce(p_data->>'header_logo_url', header_logo_url),
        host = coalesce(p_data->>'host', host),
        name = coalesce(p_data->>'name', name),
        theme = case when p_data ? 'primary_color' then jsonb_build_object('primary_color', p_data->>'primary_color') else theme end,
        title = coalesce(p_data->>'title', title),
        ad_banner_link_url = case when p_data ? 'ad_banner_link_url' then nullif(p_data->>'ad_banner_link_url', '') else ad_banner_link_url end,
        ad_banner_url = case when p_data ? 'ad_banner_url' then nullif(p_data->>'ad_banner_url', '') else ad_banner_url end,
        copyright_notice = case when p_data ? 'copyright_notice' then nullif(p_data->>'copyright_notice', '') else copyright_notice end,
        extra_links = case when p_data ? 'extra_links' then p_data->'extra_links' else extra_links end,
        facebook_url = case when p_data ? 'facebook_url' then nullif(p_data->>'facebook_url', '') else facebook_url end,
        favicon_url = case when p_data ? 'favicon_url' then nullif(p_data->>'favicon_url', '') else favicon_url end,
        flickr_url = case when p_data ? 'flickr_url' then nullif(p_data->>'flickr_url', '') else flickr_url end,
        footer_logo_url = case when p_data ? 'footer_logo_url' then nullif(p_data->>'footer_logo_url', '') else footer_logo_url end,
        github_url = case when p_data ? 'github_url' then nullif(p_data->>'github_url', '') else github_url end,
        instagram_url = case when p_data ? 'instagram_url' then nullif(p_data->>'instagram_url', '') else instagram_url end,
        linkedin_url = case when p_data ? 'linkedin_url' then nullif(p_data->>'linkedin_url', '') else linkedin_url end,
        new_group_details = case when p_data ? 'new_group_details' then nullif(p_data->>'new_group_details', '') else new_group_details end,
        og_image_url = case when p_data ? 'og_image_url' then nullif(p_data->>'og_image_url', '') else og_image_url end,
        photos_urls = case when p_data ? 'photos_urls' then array(select jsonb_array_elements_text(p_data->'photos_urls')) else photos_urls end,
        slack_url = case when p_data ? 'slack_url' then nullif(p_data->>'slack_url', '') else slack_url end,
        twitter_url = case when p_data ? 'twitter_url' then nullif(p_data->>'twitter_url', '') else twitter_url end,
        website_url = case when p_data ? 'website_url' then nullif(p_data->>'website_url', '') else website_url end,
        wechat_url = case when p_data ? 'wechat_url' then nullif(p_data->>'wechat_url', '') else wechat_url end,
        youtube_url = case when p_data ? 'youtube_url' then nullif(p_data->>'youtube_url', '') else youtube_url end
    where community_id = p_community_id;
end
$$ language plpgsql;

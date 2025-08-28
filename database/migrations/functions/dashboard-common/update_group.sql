-- update_group updates an existing group's information.
create or replace function update_group(
    p_community_id uuid,
    p_group_id uuid,
    p_group jsonb
)
returns void as $$
begin
    update "group" set
        name = p_group->>'name',
        slug = p_group->>'slug',
        group_category_id = (p_group->>'category_id')::uuid,

        banner_url = nullif(p_group->>'banner_url', ''),
        city = nullif(p_group->>'city', ''),
        country_code = nullif(p_group->>'country_code', ''),
        country_name = nullif(p_group->>'country_name', ''),
        description = nullif(p_group->>'description', ''),
        description_short = nullif(p_group->>'description_short', ''),
        extra_links = p_group->'extra_links',
        facebook_url = nullif(p_group->>'facebook_url', ''),
        flickr_url = nullif(p_group->>'flickr_url', ''),
        github_url = nullif(p_group->>'github_url', ''),
        instagram_url = nullif(p_group->>'instagram_url', ''),
        linkedin_url = nullif(p_group->>'linkedin_url', ''),
        logo_url = nullif(p_group->>'logo_url', ''),
        photos_urls = case
            when p_group ? 'photos_urls' and jsonb_typeof(p_group->'photos_urls') != 'null' then
                array(select jsonb_array_elements_text(p_group->'photos_urls'))
            else null
        end,
        region_id = case when p_group->>'region_id' <> '' then (p_group->>'region_id')::uuid else null end,
        slack_url = nullif(p_group->>'slack_url', ''),
        state = nullif(p_group->>'state', ''),
        tags = case
            when p_group ? 'tags' and jsonb_typeof(p_group->'tags') != 'null' then
                array(select jsonb_array_elements_text(p_group->'tags'))
            else null
        end,
        twitter_url = nullif(p_group->>'twitter_url', ''),
        website_url = nullif(p_group->>'website_url', ''),
        wechat_url = nullif(p_group->>'wechat_url', ''),
        youtube_url = nullif(p_group->>'youtube_url', '')
    where group_id = p_group_id
    and community_id = p_community_id
    and deleted = false;

    if not found then
        raise exception 'group not found';
    end if;
end;
$$ language plpgsql;

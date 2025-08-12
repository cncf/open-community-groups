-- update_group updates an existing group's information.
create or replace function update_group(
    p_group_id uuid,
    p_group jsonb
)
returns void as $$
begin
    update "group" set
        name = p_group->>'name',
        slug = p_group->>'slug',
        group_category_id = (p_group->>'category_id')::uuid,
        description = p_group->>'description',

        banner_url = p_group->>'banner_url',
        city = p_group->>'city',
        country_code = p_group->>'country_code',
        country_name = p_group->>'country_name',
        extra_links = p_group->'extra_links',
        facebook_url = p_group->>'facebook_url',
        flickr_url = p_group->>'flickr_url',
        github_url = p_group->>'github_url',
        instagram_url = p_group->>'instagram_url',
        linkedin_url = p_group->>'linkedin_url',
        logo_url = p_group->>'logo_url',
        photos_urls = case when p_group->'photos_urls' is not null then array(select jsonb_array_elements_text(p_group->'photos_urls')) else null end,
        region_id = (p_group->>'region_id')::uuid,
        slack_url = p_group->>'slack_url',
        state = p_group->>'state',
        tags = case when p_group->'tags' is not null then array(select jsonb_array_elements_text(p_group->'tags')) else null end,
        twitter_url = p_group->>'twitter_url',
        website_url = p_group->>'website_url',
        wechat_url = p_group->>'wechat_url',
        youtube_url = p_group->>'youtube_url'
    where group_id = p_group_id
    and deleted = false;

    if not found then
        raise exception 'group not found';
    end if;
end;
$$ language plpgsql;

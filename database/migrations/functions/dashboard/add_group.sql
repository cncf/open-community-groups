-- add_group adds a new group to the database.
create or replace function add_group(
    p_community_id uuid,
    p_group jsonb
)
returns uuid as $$
    insert into "group" (
        community_id,
        name,
        slug,
        group_category_id,
        description,

        banner_url,
        city,
        country_code,
        country_name,
        extra_links,
        facebook_url,
        flickr_url,
        github_url,
        instagram_url,
        linkedin_url,
        logo_url,
        photos_urls,
        region_id,
        slack_url,
        state,
        tags,
        twitter_url,
        website_url,
        wechat_url,
        youtube_url
    ) values (
        p_community_id,
        p_group->>'name',
        p_group->>'slug',
        (p_group->>'category_id')::uuid,
        p_group->>'description',

        p_group->>'banner_url',
        p_group->>'city',
        p_group->>'country_code',
        p_group->>'country_name',
        p_group->'extra_links',
        p_group->>'facebook_url',
        p_group->>'flickr_url',
        p_group->>'github_url',
        p_group->>'instagram_url',
        p_group->>'linkedin_url',
        p_group->>'logo_url',
        case when p_group->'photos_urls' is not null then array(select jsonb_array_elements_text(p_group->'photos_urls')) else null end,
        (p_group->>'region_id')::uuid,
        p_group->>'slack_url',
        p_group->>'state',
        case when p_group->'tags' is not null then array(select jsonb_array_elements_text(p_group->'tags')) else null end,
        p_group->>'twitter_url',
        p_group->>'website_url',
        p_group->>'wechat_url',
        p_group->>'youtube_url'
    )
    returning group_id;
$$ language sql;

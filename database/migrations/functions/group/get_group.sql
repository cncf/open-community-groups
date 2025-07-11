-- Returns detailed information about a group by its slug and community ID.
create or replace function get_group(p_community_id uuid, p_group_slug text)
returns json as $$
    select json_strip_nulls(json_build_object(
        'banner_url', g.banner_url,
        'category_name', gc.name,
        'city', g.city,
        'country_code', g.country_code,
        'country_name', g.country_name,
        'created_at', floor(extract(epoch from g.created_at)),
        'description', g.description,
        'extra_links', g.extra_links,
        'facebook_url', g.facebook_url,
        'flickr_url', g.flickr_url,
        'github_url', g.github_url,
        'instagram_url', g.instagram_url,
        'latitude', st_y(g.location::geometry),
        'linkedin_url', g.linkedin_url,
        'logo_url', g.logo_url,
        'longitude', st_x(g.location::geometry),
        'name', g.name,
        'photos_urls', g.photos_urls,
        'region_name', r.name,
        'slack_url', g.slack_url,
        'slug', g.slug,
        'state', g.state,
        'tags', g.tags,
        'twitter_url', g.twitter_url,
        'website_url', g.website_url,
        'wechat_url', g.wechat_url,
        'youtube_url', g.youtube_url
    )) as json_data
    from "group" g
    join group_category gc using (group_category_id)
    left join region r using (region_id)
    where g.community_id = p_community_id
    and g.slug = p_group_slug
    and g.active = true;
$$ language sql;
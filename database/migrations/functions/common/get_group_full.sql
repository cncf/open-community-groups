-- Returns full information about a group by its ID.
create or replace function get_group_full(p_group_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'active', g.active,
        'category', json_build_object(
            'group_category_id', gc.group_category_id,
            'name', gc.name,
            'normalized_name', gc.normalized_name,
            'order', gc.order
        ),
        'created_at', floor(extract(epoch from g.created_at)),
        'group_id', g.group_id,
        'members_count', (
            select count(*)
            from group_member
            where group_id = g.group_id
        ),
        'name', g.name,
        'slug', g.slug,

        'banner_url', g.banner_url,
        'city', g.city,
        'country_code', g.country_code,
        'country_name', g.country_name,
        'description', g.description,
        'description_short', g.description_short,
        'extra_links', g.extra_links,
        'facebook_url', g.facebook_url,
        'flickr_url', g.flickr_url,
        'github_url', g.github_url,
        'instagram_url', g.instagram_url,
        'latitude', st_y(g.location::geometry),
        'linkedin_url', g.linkedin_url,
        'logo_url', g.logo_url,
        'longitude', st_x(g.location::geometry),
        'photos_urls', g.photos_urls,
        'region', case when r.region_id is not null then
            json_build_object(
                'region_id', r.region_id,
                'name', r.name,
                'normalized_name', r.normalized_name,
                'order', r.order
            )
        else null end,
        'slack_url', g.slack_url,
        'state', g.state,
        'tags', g.tags,
        'twitter_url', g.twitter_url,
        'wechat_url', g.wechat_url,
        'website_url', g.website_url,
        'youtube_url', g.youtube_url,

        'organizers', (
            select coalesce(json_agg(json_strip_nulls(json_build_object(
                'user_id', u.user_id,
                'name', u.name,

                'company', u.company,
                'facebook_url', u.facebook_url,
                'linkedin_url', u.linkedin_url,
                'photo_url', u.photo_url,
                'title', u.title,
                'twitter_url', u.twitter_url,
                'website_url', u.website_url
            )) order by gt."order" nulls last, u.name), '[]')
            from group_team gt
            join "user" u using (user_id)
            where gt.group_id = g.group_id
            and gt.role = 'organizer'
            and gt.accepted = true
        )
    )) as json_data
    from "group" g
    join group_category gc using (group_category_id)
    left join region r using (region_id)
    where g.group_id = p_group_id;
$$ language sql;

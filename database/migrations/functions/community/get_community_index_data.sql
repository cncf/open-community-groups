-- Returns the information needed to render the community index page.
create or replace function get_community_index_data(p_community_id uuid)
returns json as $$
    select json_strip_nulls(json_build_object(
        'community', json_build_object(
            'banners_urls', banners_urls,
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
            'photos_urls', photos_urls,
            'slack_url', slack_url,
            'title', title,
            'twitter_url', twitter_url,
            'wechat_url', wechat_url,
            'youtube_url', youtube_url
        ),
        'groups', (
            select coalesce(json_agg(json_build_object(
                'city', g.city,
                'country', g.country,
                'icon_url', g.icon_url,
                'name', g.name,
                'region_name', r.name,
                'slug', g.slug
            )), '[]')
            from "group" g
            join region r using (region_id)
            where g.community_id = $1
        ),
        'upcoming_in_person_events', (
            select coalesce(json_agg(json_build_object(
                'city', coalesce(event_city, group_city),
                'group_name', group_name,
                'icon_url', icon_url,
                'slug', slug,
                'starts_at', floor(extract(epoch from starts_at)),
                'title', title
            )), '[]')
            from (
                select
                    e.city as event_city,
                    g.city as group_city,
                    g.name as group_name,
                    e.icon_url,
                    e.slug,
                    e.starts_at,
                    e.title
                from event e
                join "group" g using (group_id)
                where g.community_id = $1
                and e.icon_url is not null
                and e.starts_at > now()
                and e.cancelled = false
                and e.postponed = false
                and e.event_kind_id = 'in-person'
                order by e.starts_at asc
                limit 10
            ) events
        ),
        'upcoming_online_events', (
            select coalesce(json_agg(json_build_object(
                'city', coalesce(event_city, group_city),
                'group_name', group_name,
                'icon_url', icon_url,
                'slug', slug,
                'starts_at', floor(extract(epoch from starts_at)),
                'title', title
            )), '[]')
            from (
                select
                    e.city as event_city,
                    g.city as group_city,
                    g.name as group_name,
                    e.icon_url,
                    e.slug,
                    e.starts_at,
                    e.title
                from event e
                join "group" g using (group_id)
                where g.community_id = $1
                and e.icon_url is not null
                and e.starts_at > now()
                and e.cancelled = false
                and e.postponed = false
                and e.event_kind_id = 'virtual'
                order by e.starts_at asc
                limit 10
            ) events
        )
    )) as json_data
    from community
    where community_id = p_community_id;
$$ language sql;

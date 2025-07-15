-- Returns detailed information about an event by its slug, group slug and community ID.
create or replace function get_event(p_community_id uuid, p_group_slug text, p_event_slug text)
returns json as $$
    select json_strip_nulls(json_build_object(
        'canceled', e.canceled,
        'category_name', ec.name,
        'created_at', floor(extract(epoch from e.created_at)),
        'description', e.description,
        'event_id', e.event_id,
        'kind', e.event_kind_id,
        'name', e.name,
        'published', e.published,
        'slug', e.slug,
        'timezone', e.timezone,
        
        'banner_url', e.banner_url,
        'capacity', e.capacity,
        'description_short', e.description_short,
        'ends_at', floor(extract(epoch from e.ends_at)),
        'logo_url', e.logo_url,
        'meetup_url', e.meetup_url,
        'photos_urls', e.photos_urls,
        'published_at', floor(extract(epoch from e.published_at)),
        'recording_url', e.recording_url,
        'registration_required', e.registration_required,
        'starts_at', floor(extract(epoch from e.starts_at)),
        'streaming_url', e.streaming_url,
        'tags', e.tags,
        'venue_address', e.venue_address,
        'venue_city', e.venue_city,
        'venue_name', e.venue_name,
        'venue_zip_code', e.venue_zip_code,
        
        'group', json_build_object(
            'name', g.name,
            'slug', g.slug,
            'category_name', gc.name
        ),
        'hosts', (
            select coalesce(json_agg(json_strip_nulls(json_build_object(
                'user_id', u.user_id,
                'first_name', u.first_name,
                'last_name', u.last_name,
                'company', u.company,
                'title', u.title,
                'photo_url', u.photo_url,
                'facebook_url', u.facebook_url,
                'linkedin_url', u.linkedin_url,
                'twitter_url', u.twitter_url,
                'website_url', u.website_url
            )) order by u.first_name, u.last_name), '[]')
            from event_host eh
            join "user" u using (user_id)
            where eh.event_id = e.event_id
        ),
        'organizers', (
            select coalesce(json_agg(json_strip_nulls(json_build_object(
                'user_id', u.user_id,
                'first_name', u.first_name,
                'last_name', u.last_name,
                'company', u.company,
                'title', u.title,
                'photo_url', u.photo_url,
                'facebook_url', u.facebook_url,
                'linkedin_url', u.linkedin_url,
                'twitter_url', u.twitter_url,
                'website_url', u.website_url
            )) order by gt."order" nulls last, u.first_name, u.last_name), '[]')
            from group_team gt
            join "user" u using (user_id)
            where gt.group_id = g.group_id
            and gt.role = 'organizer'
        ),
        'sessions', (
            select coalesce(json_agg(json_strip_nulls(json_build_object(
                'session_id', s.session_id,
                'name', s.name,
                'description', s.description,
                'starts_at', floor(extract(epoch from s.starts_at)),
                'ends_at', floor(extract(epoch from s.ends_at)),
                'kind', s.session_kind_id,
                'location', s.location,
                'recording_url', s.recording_url,
                'streaming_url', s.streaming_url,
                'speakers', (
                    select coalesce(json_agg(json_strip_nulls(json_build_object(
                        'user_id', u.user_id,
                        'first_name', u.first_name,
                        'last_name', u.last_name,
                        'company', u.company,
                        'title', u.title,
                        'photo_url', u.photo_url,
                        'facebook_url', u.facebook_url,
                        'linkedin_url', u.linkedin_url,
                        'twitter_url', u.twitter_url,
                        'website_url', u.website_url
                    )) order by ss.featured desc, u.first_name, u.last_name), '[]')
                    from session_speaker ss
                    join "user" u using (user_id)
                    where ss.session_id = s.session_id
                )
            )) order by s.starts_at), '[]')
            from session s
            where s.event_id = e.event_id
        )
    )) as json_data
    from event e
    join "group" g using (group_id)
    join group_category gc on g.group_category_id = gc.group_category_id
    join event_category ec using (event_category_id)
    where g.community_id = p_community_id
    and g.slug = p_group_slug
    and e.slug = p_event_slug
    and g.active = true
    and e.published = true;
$$ language sql;
-- Returns full information about an event by its ID.
create or replace function get_event_full(p_event_id uuid)
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
        'latitude', st_y(g.location::geometry),
        'logo_url', e.logo_url,
        'longitude', st_x(g.location::geometry),
        'meetup_url', e.meetup_url,
        'photos_urls', e.photos_urls,
        'published_at', floor(extract(epoch from e.published_at)),
        'recording_url', e.recording_url,
        'registration_required', e.registration_required,
        'starts_at', floor(extract(epoch from e.starts_at)),
        'streaming_url', e.streaming_url,
        'tags', e.tags,
        'timezone_abbr', e.timezone_abbr,
        'venue_address', e.venue_address,
        'venue_city', e.venue_city,
        'venue_name', e.venue_name,
        'venue_zip_code', e.venue_zip_code,
        
        'group', get_group_summary(g.group_id),
        'hosts', (
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
            )) order by u.name), '[]')
            from event_host eh
            join "user" u using (user_id)
            where eh.event_id = e.event_id
        ),
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
        ),
        'sessions', (
            select coalesce(json_agg(json_strip_nulls(json_build_object(
                'description', s.description,
                'ends_at', floor(extract(epoch from s.ends_at)),
                'session_id', s.session_id,
                'kind', s.session_kind_id,
                'name', s.name,
                'starts_at', floor(extract(epoch from s.starts_at)),
                
                'location', s.location,
                'recording_url', s.recording_url,
                'streaming_url', s.streaming_url,
                
                'speakers', (
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
                    )) order by ss.featured desc, u.name), '[]')
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
    join event_category ec using (event_category_id)
    where e.event_id = p_event_id;
$$ language sql;
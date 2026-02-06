-- Returns full information about an event.
create or replace function get_event_full(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    -- Build full event payload with related entities and computed fields
    select jsonb_strip_nulls(
        jsonb_build_object(
            -- Include core event fields
            'canceled', e.canceled,
            'category_name', ec.name,
            'created_at', floor(extract(epoch from e.created_at)),
            'description', e.description,
            'event_id', e.event_id,
            'kind', e.event_kind_id,
            'name', e.name,
            'published', e.published,
            'slug', e.slug,
            'timezone', e.timezone
        )
        -- Include optional fields and nested related collections
        || jsonb_build_object(
            'banner_mobile_url', e.banner_mobile_url,
            'banner_url', e.banner_url,
            'capacity', e.capacity,
            'cfs_description', e.cfs_description,
            'cfs_enabled', e.cfs_enabled,
            'cfs_ends_at', floor(extract(epoch from e.cfs_ends_at)),
            'cfs_starts_at', floor(extract(epoch from e.cfs_starts_at)),
            'description_short', e.description_short,
            'ends_at', floor(extract(epoch from e.ends_at)),
            'latitude', st_y(e.location::geometry),
            'logo_url', coalesce(e.logo_url, g.logo_url, c.logo_url),
            'longitude', st_x(e.location::geometry),
            'meeting_error', e.meeting_error,
            'meeting_hosts', e.meeting_hosts,
            'meeting_in_sync', e.meeting_in_sync,
            'meeting_join_url', coalesce(m_event.join_url, e.meeting_join_url),
            'meeting_password', m_event.password,
            'meeting_provider', e.meeting_provider_id,
            'meeting_recording_url', coalesce(m_event.recording_url, e.meeting_recording_url),
            'meeting_requested', e.meeting_requested,
            'meetup_url', e.meetup_url,
            'photos_urls', e.photos_urls,
            'published_at', floor(extract(epoch from e.published_at)),
            'registration_required', e.registration_required,
            'starts_at', floor(extract(epoch from e.starts_at)),
            'tags', e.tags,
            'venue_address', e.venue_address,
            'venue_city', e.venue_city,
            'venue_country_code', e.venue_country_code,
            'venue_country_name', e.venue_country_name,
            'venue_name', e.venue_name,
            'venue_state', e.venue_state,
            'venue_zip_code', e.venue_zip_code,

            -- Include community and group summaries
            'community', get_community_summary(g.community_id),
            'group', get_group_summary(g.community_id, g.group_id),
            -- Include event hosts profiles
            'hosts', (
                select coalesce(json_agg(json_strip_nulls(json_build_object(
                    'user_id', u.user_id,
                    'username', u.username,

                    'bio', u.bio,
                    'company', u.company,
                    'facebook_url', u.facebook_url,
                    'linkedin_url', u.linkedin_url,
                    'name', u.name,
                    'photo_url', u.photo_url,
                    'title', u.title,
                    'twitter_url', u.twitter_url,
                    'website_url', u.website_url
                )) order by u.name), '[]')
                from event_host eh
                join "user" u using (user_id)
                where eh.event_id = e.event_id
            ),
            -- Include legacy hosts for backward compatibility
            'legacy_hosts', (
                select coalesce(json_agg(json_strip_nulls(json_build_object(
                    'bio', leh.bio,
                    'name', leh.name,
                    'photo_url', leh.photo_url,
                    'title', leh.title
                )) order by leh.name), '[]')
                from legacy_event_host leh
                where leh.event_id = e.event_id
            ),
            -- Include legacy speakers for backward compatibility
            'legacy_speakers', (
                select coalesce(json_agg(json_strip_nulls(json_build_object(
                    'bio', les.bio,
                    'name', les.name,
                    'photo_url', les.photo_url,
                    'title', les.title
                )) order by les.name), '[]')
                from legacy_event_speaker les
                where les.event_id = e.event_id
            ),
            -- Include group organizers
            'organizers', (
                select coalesce(json_agg(json_strip_nulls(json_build_object(
                    'user_id', u.user_id,
                    'username', u.username,

                    'bio', u.bio,
                    'company', u.company,
                    'facebook_url', u.facebook_url,
                    'linkedin_url', u.linkedin_url,
                    'name', u.name,
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
            ),
            -- Include remaining capacity when event capacity is set
            'remaining_capacity',
                case
                    when e.capacity is null then null
                    else greatest(e.capacity - coalesce(ea.attendee_count, 0), 0)
                end,
            -- Include sessions grouped by local event day
            'sessions', (
                with
                -- Build session payloads for this event
                event_sessions as (
                    select
                        to_char((s.starts_at at time zone e.timezone)::date, 'YYYY-MM-DD') as day,
                        s.starts_at,
                        json_strip_nulls(json_build_object(
                            'session_id', s.session_id,
                            'kind', s.session_kind_id,
                            'name', s.name,
                            'starts_at', floor(extract(epoch from s.starts_at)),

                            'cfs_submission_id', s.cfs_submission_id,
                            'description', coalesce(s.description, sp.description),
                            'ends_at', floor(extract(epoch from s.ends_at)),
                            'location', s.location,
                            'meeting_error', s.meeting_error,
                            'meeting_hosts', s.meeting_hosts,
                            'meeting_in_sync', s.meeting_in_sync,
                            'meeting_join_url', coalesce(m_session.join_url, s.meeting_join_url),
                            'meeting_password', m_session.password,
                            'meeting_provider', s.meeting_provider_id,
                            'meeting_recording_url', coalesce(m_session.recording_url, s.meeting_recording_url),
                            'meeting_requested', s.meeting_requested,

                            'speakers', coalesce(
                                (
                                    select json_agg(json_strip_nulls(json_build_object(
                                        'user_id', u.user_id,
                                        'username', u.username,

                                        'bio', u.bio,
                                        'company', u.company,
                                        'facebook_url', u.facebook_url,
                                        'featured', ss.featured,
                                        'linkedin_url', u.linkedin_url,
                                        'name', u.name,
                                        'photo_url', u.photo_url,
                                        'title', u.title,
                                        'twitter_url', u.twitter_url,
                                        'website_url', u.website_url
                                    )) order by ss.featured desc, u.name)
                                    from session_speaker ss
                                    join "user" u using (user_id)
                                    where ss.session_id = s.session_id
                                ),
                                (
                                    select json_agg(json_strip_nulls(json_build_object(
                                        'user_id', u.user_id,
                                        'username', u.username,

                                        'bio', u.bio,
                                        'company', u.company,
                                        'facebook_url', u.facebook_url,
                                        'featured', false,
                                        'linkedin_url', u.linkedin_url,
                                        'name', u.name,
                                        'photo_url', u.photo_url,
                                        'title', u.title,
                                        'twitter_url', u.twitter_url,
                                        'website_url', u.website_url
                                    )) order by
                                        case when u.user_id = sp.user_id then 0 else 1 end,
                                        u.name
                                    )
                                    from "user" u
                                    where u.user_id in (sp.user_id, sp.co_speaker_user_id)
                                ),
                                '[]'
                            )
                        )) as session_json
                    from session s
                    left join meeting m_session on m_session.session_id = s.session_id
                    left join cfs_submission cs on cs.cfs_submission_id = s.cfs_submission_id
                    left join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
                    where s.event_id = e.event_id
                ),
                -- Group session payloads by day
                event_sessions_grouped as (
                    select day, json_agg(session_json order by starts_at) as sessions
                    from event_sessions
                    group by day
                )
                select coalesce(
                    (select jsonb_object_agg(day, sessions order by day) from event_sessions_grouped),
                    '{}'::jsonb
                )::json
            ),
            -- Include event speakers
            'speakers', (
                select coalesce(json_agg(json_strip_nulls(json_build_object(
                    'user_id', u.user_id,
                    'username', u.username,

                    'bio', u.bio,
                    'company', u.company,
                    'facebook_url', u.facebook_url,
                    'featured', es.featured,
                    'linkedin_url', u.linkedin_url,
                    'name', u.name,
                    'photo_url', u.photo_url,
                    'title', u.title,
                    'twitter_url', u.twitter_url,
                    'website_url', u.website_url
                )) order by es.featured desc, u.name), '[]')
                from event_speaker es
                join "user" u using (user_id)
                where es.event_id = e.event_id
            ),
            -- Include event sponsors
            'sponsors', (
                select coalesce(json_agg(json_strip_nulls(json_build_object(
                    'group_sponsor_id', gs.group_sponsor_id,
                    'level', es.level,
                    'logo_url', gs.logo_url,
                    'name', gs.name,

                    'website_url', gs.website_url
                )) order by gs.name), '[]')
                from event_sponsor es
                join group_sponsor gs on gs.group_sponsor_id = es.group_sponsor_id
                where es.event_id = e.event_id
            )
        )
    )::json as json_data
    from event e
    join "group" g using (group_id)
    join community c on c.community_id = g.community_id
    join event_category ec using (event_category_id)
    left join meeting m_event on m_event.event_id = e.event_id
    left join (
        select event_id, count(*)::int as attendee_count
        from event_attendee
        group by event_id
    ) ea on ea.event_id = e.event_id
    where e.event_id = p_event_id
    and g.group_id = p_group_id
    and g.community_id = p_community_id;
$$ language sql;

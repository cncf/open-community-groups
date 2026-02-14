-- enqueue_due_event_reminders enqueues reminders for events starting within 24h.
create or replace function enqueue_due_event_reminders(p_base_url text)
returns int as $$
declare
    v_base_url text;
    v_event record;
    v_recipients uuid[];
    v_reminders_enqueued int := 0;
begin
    -- Ensure only one worker enqueues due reminders per transaction window
    if not pg_try_advisory_xact_lock(hashtextextended('ocg:event-reminder-enqueue', 0)) then
        return 0;
    end if;

    -- Normalize base URL used to build event links
    v_base_url := regexp_replace(coalesce(p_base_url, ''), '/+$', '');

    -- Fetch and lock due events that still require reminder evaluation
    for v_event in
        select
            c.display_name as community_display_name,
            c.name as community_name,
            e.canceled,
            e.event_id,
            e.event_kind_id,
            e.name as event_name,
            e.published,
            e.slug as event_slug,
            e.starts_at,
            e.timezone,
            g.name as group_name,
            g.slug as group_slug,
            gc.name as group_category_name,

            coalesce(e.logo_url, g.logo_url, c.logo_url) as logo_url,
            coalesce(m.join_url, e.meeting_join_url) as meeting_join_url,
            m.password as meeting_password,
            s.theme,
            e.venue_address,
            e.venue_city,
            e.venue_country_code,
            e.venue_country_name,
            e.venue_name,
            e.venue_state,
            e.venue_zip_code
        from event e
        join "group" g using (group_id)
        join group_category gc using (group_category_id)
        join community c on c.community_id = g.community_id
        left join meeting m on m.event_id = e.event_id
        left join lateral (
            select site.theme
            from site
            order by site.created_at desc
            limit 1
        ) s on true
        where c.active = true
        and e.deleted = false
        and e.canceled = false
        and e.published = true
        and g.active = true
        and g.deleted = false
        and e.starts_at is not null
        and e.event_reminder_enabled = true
        and e.event_reminder_sent_at is null
        and e.starts_at > current_timestamp
        and e.starts_at <= current_timestamp + interval '24 hours'
        and e.event_reminder_evaluated_for_starts_at is distinct from e.starts_at
        order by e.starts_at asc, e.event_id asc
        for update of e skip locked
    loop
        -- Collect verified attendees and speakers to notify
        select coalesce(array_agg(recipient.user_id order by recipient.user_id), '{}')
        into v_recipients
        from (
            -- Attendees
            select ea.user_id
            from event_attendee ea
            join "user" u using (user_id)
            where ea.event_id = v_event.event_id
            and u.email_verified = true

            union

            -- Speakers
            select es.user_id
            from event_speaker es
            join "user" u using (user_id)
            where es.event_id = v_event.event_id
            and u.email_verified = true
        ) recipient;

        -- Enqueue reminder notifications when recipients exist
        if coalesce(array_length(v_recipients, 1), 0) > 0 then
            perform enqueue_notification(
                'event-reminder',
                jsonb_strip_nulls(
                    jsonb_build_object(
                        'event', jsonb_build_object(
                            'canceled', v_event.canceled,
                            'community_display_name', v_event.community_display_name,
                            'community_name', v_event.community_name,
                            'event_id', v_event.event_id,
                            'group_category_name', v_event.group_category_name,
                            'group_name', v_event.group_name,
                            'group_slug', v_event.group_slug,
                            'kind', v_event.event_kind_id,
                            'logo_url', v_event.logo_url,
                            'meeting_join_url', v_event.meeting_join_url,
                            'meeting_password', v_event.meeting_password,
                            'name', v_event.event_name,
                            'published', v_event.published,
                            'slug', v_event.event_slug,
                            'starts_at', extract(epoch from v_event.starts_at)::bigint,
                            'timezone', v_event.timezone,
                            'venue_address', v_event.venue_address,
                            'venue_city', v_event.venue_city,
                            'venue_country_code', v_event.venue_country_code,
                            'venue_country_name', v_event.venue_country_name,
                            'venue_name', v_event.venue_name,
                            'venue_state', v_event.venue_state,
                            'zip_code', v_event.venue_zip_code
                        ),
                        'link', format(
                            '%s/%s/group/%s/event/%s',
                            v_base_url,
                            v_event.community_name,
                            v_event.group_slug,
                            v_event.event_slug
                        ),
                        'theme', v_event.theme
                    )
                ),
                '[]'::jsonb,
                v_recipients
            );

            -- Mark the current start time as evaluated and reminders as sent
            update event set
                event_reminder_evaluated_for_starts_at = starts_at,
                event_reminder_sent_at = now()
            where event_id = v_event.event_id;

            v_reminders_enqueued := v_reminders_enqueued + array_length(v_recipients, 1);
        else
            -- Mark the current start time as evaluated when there are no recipients
            update event set
                event_reminder_evaluated_for_starts_at = starts_at
            where event_id = v_event.event_id;
        end if;
    end loop;

    return v_reminders_enqueued;
end;
$$ language plpgsql;

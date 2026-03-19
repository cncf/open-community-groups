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
            c.community_id,
            c.name as community_name,
            e.event_id,
            e.slug as event_slug,
            e.starts_at,
            g.group_id,
            g.slug as group_slug,
            s.theme
        from event e
        join "group" g using (group_id)
        join community c on c.community_id = g.community_id
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
                        'event',
                            get_event_summary(
                                v_event.community_id,
                                v_event.group_id,
                                v_event.event_id
                            )::jsonb,
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

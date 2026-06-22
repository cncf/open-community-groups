-- enqueue_due_event_reminders enqueues reminders for events starting within 24h.
create or replace function enqueue_due_event_reminders(p_base_url text)
returns int as $$
declare
    v_attendee_recipients uuid[];
    v_base_url text;
    v_event record;
    v_recipient_count int;
    v_reminders_enqueued int := 0;
    v_speaker_only_recipients uuid[];
    v_template_data jsonb;
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
            c.alliance_id,
            c.name as alliance_name,
            e.event_id,
            e.slug as event_slug,
            e.starts_at,
            g.group_id,
            g.slug as group_slug,
            g.slug_pretty as group_slug_pretty,
            s.theme
        from event e
        join "group" g using (group_id)
        join alliance c on c.alliance_id = g.alliance_id
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
        and e.test_event = false
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
        -- Collect verified attendees who should see attendance cancellation copy
        select coalesce(array_agg(ea.user_id order by ea.user_id), '{}')
        into v_attendee_recipients
        from event_attendee ea
        join "user" u using (user_id)
        where ea.event_id = v_event.event_id
        and ea.status = 'confirmed'
        and u.email_verified = true;

        -- Collect verified speaker-only users who cannot cancel attendance
        select coalesce(array_agg(es.user_id order by es.user_id), '{}')
        into v_speaker_only_recipients
        from event_speaker es
        join "user" u using (user_id)
        left join event_attendee ea
            on ea.event_id = es.event_id
            and ea.user_id = es.user_id
            and ea.status = 'confirmed'
        where es.event_id = v_event.event_id
        and ea.user_id is null
        and u.email_verified = true;

        -- Count recipient groups before building notification data
        v_recipient_count :=
            cardinality(v_attendee_recipients) + cardinality(v_speaker_only_recipients);

        -- Enqueue reminder notifications when recipients exist
        if v_recipient_count > 0 then
            -- Build base template data shared by all reminder recipients
            v_template_data := jsonb_strip_nulls(
                jsonb_build_object(
                    'event',
                        get_event_summary(
                            v_event.alliance_id,
                            v_event.group_id,
                            v_event.event_id
                        )::jsonb,
                    'link', format(
                        '%s/%s/group/%s/event/%s',
                        v_base_url,
                        v_event.alliance_name,
                        coalesce(v_event.group_slug_pretty, v_event.group_slug),
                        v_event.event_slug
                    ),
                    'dashboard_link', format('%s/dashboard/user?tab=events', v_base_url),
                    'theme', v_event.theme
                )
            );

            -- Enqueue attendee reminders with attendance cancellation copy enabled
            if cardinality(v_attendee_recipients) > 0 then
                perform enqueue_notification(
                    'event-reminder',
                    v_template_data || jsonb_build_object('show_attendance_cancellation_copy', true),
                    '[]'::jsonb,
                    v_attendee_recipients
                );
            end if;

            -- Enqueue speaker-only reminders without attendance cancellation copy
            if cardinality(v_speaker_only_recipients) > 0 then
                perform enqueue_notification(
                    'event-reminder',
                    v_template_data || jsonb_build_object('show_attendance_cancellation_copy', false),
                    '[]'::jsonb,
                    v_speaker_only_recipients
                );
            end if;

            -- Mark the current start time as evaluated and reminders as sent
            update event set
                event_reminder_evaluated_for_starts_at = starts_at,
                event_reminder_sent_at = now()
            where event_id = v_event.event_id;

            -- Track notifications created for both reminder recipient groups
            v_reminders_enqueued := v_reminders_enqueued + v_recipient_count;
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

-- Enqueues the opening email of every survey that is now open and returns the
-- number of notifications enqueued. Candidates are picked without row locks;
-- each one then locks its event for share and its survey for update, skipping
-- rows other transactions hold, and re-checks every condition under those
-- locks. Recipients are the eligible users with verified emails; test events
-- never email. Each handled survey is marked processed, even without
-- recipients, so it never emails again. The survey link opens the survey in
-- the user dashboard; it is stored relative to the site root and completed by
-- the server.
create or replace function enqueue_due_event_survey_notifications()
returns int as $$
declare
    v_candidate record;
    v_community community;
    v_event event;
    v_event_survey event_survey;
    v_group "group";
    v_notification_ids uuid[];
    v_notifications_enqueued int := 0;
    v_recipients uuid[];
    v_template_data jsonb;
    v_theme jsonb;
begin
    -- Ensure only one worker enqueues survey emails per transaction window
    if not pg_try_advisory_xact_lock(hashtextextended('ocg:event-survey-notification-enqueue', 0)) then
        return 0;
    end if;

    -- Read the site theme shared by every email of this run
    v_theme := site_theme();

    -- Walk the surveys that look due without locking them yet
    for v_candidate in
        select
            s.event_id,
            s.event_survey_id
        from event_survey s
        join event e on e.event_id = s.event_id
        join "group" g on g.group_id = e.group_id
        join community c on c.community_id = g.community_id
        where s.status = 'ready'
        and s.open_notification_processed_at is null
        and s.closed_at is null
        and is_event_survey_public(s, e, g, c)
        and event_survey_state(s, e) = 'open'
        order by event_survey_effective_opens_at(s, e), s.event_survey_id
    loop
        -- Lock the event for share, skipping events another transaction is changing
        select e.*
        into v_event
        from event e
        where e.event_id = v_candidate.event_id
        for share of e skip locked;

        -- Leave events busy elsewhere for a later run
        if not found then
            continue;
        end if;

        -- Lock the survey, skipping surveys another transaction is changing
        select s.*
        into v_event_survey
        from event_survey s
        where s.event_survey_id = v_candidate.event_survey_id
        and s.event_id = v_event.event_id
        for update of s skip locked;

        -- Leave surveys busy elsewhere for a later run
        if not found then
            continue;
        end if;

        -- Load the current group and community of the event
        select g.* into v_group from "group" g where g.group_id = v_event.group_id;
        select c.* into v_community from community c where c.community_id = v_group.community_id;

        -- Skip surveys that stopped being due under the locks
        if not is_event_survey_public(v_event_survey, v_event, v_group, v_community)
            or event_survey_state(v_event_survey, v_event) <> 'open'
            or v_event_survey.open_notification_processed_at is not null
        then
            continue;
        end if;

        -- Test events never email their attendees
        if v_event.test_event then
            v_recipients := '{}'::uuid[];

        -- Email the eligible users with verified emails
        else
            select coalesce(array_agg(eu.user_id order by eu.user_id), '{}')
            into v_recipients
            from event_survey_eligible_users(v_event.event_id, v_event_survey.audience) eu
            join "user" u on u.user_id = eu.user_id
            where u.email_verified = true;
        end if;

        -- Start the survey without enqueued notifications
        v_notification_ids := '{}'::uuid[];

        -- Enqueue the opening email when there are recipients
        if cardinality(v_recipients) > 0 then
            -- Build the template data of the opening email
            v_template_data := jsonb_strip_nulls(jsonb_build_object(
                'anonymous', v_event_survey.anonymous,
                'event', get_event_summary(
                    v_community.community_id,
                    v_group.group_id,
                    v_event.event_id
                )::jsonb,
                'link', '/dashboard/user?tab=events&event_survey_id=' || v_event_survey.event_survey_id,
                'survey_title', v_event_survey.title,
                'theme', v_theme,

                'closes_at', epoch_seconds(v_event_survey.closes_at)
            ));

            -- Enqueue one email per recipient, applying their preferences
            v_notification_ids := enqueue_notification(
                'event-survey-opened',
                v_template_data,
                '[]'::jsonb,
                v_recipients,
                array[v_group.group_id]
            );
        end if;

        -- Mark the opening email handled so it is never sent again
        update event_survey set
            open_notification_processed_at = current_timestamp,
            open_notification_recipients = cardinality(v_notification_ids)
        where event_survey_id = v_event_survey.event_survey_id;

        -- Count the notifications enqueued for this survey
        v_notifications_enqueued := v_notifications_enqueued + cardinality(v_notification_ids);
    end loop;

    -- Return the number of notifications enqueued
    return v_notifications_enqueued;
end;
$$ language plpgsql;

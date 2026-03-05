-- Returns paginated upcoming events where the user participates.
create or replace function list_user_events(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse pagination filters.
        filters as (
            select
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value
        ),
        -- Collect attendee events.
        attendee_events as (
            select
                e.event_id,
                e.group_id,
                e.starts_at,
                g.community_id,
                'Attendee'::text as role
            from event_attendee ea
            join event e using (event_id)
            join "group" g using (group_id)
            where ea.user_id = p_user_id
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.starts_at > now()
            and g.active = true
            and g.deleted = false
        ),
        -- Collect host events.
        host_events as (
            select
                e.event_id,
                e.group_id,
                e.starts_at,
                g.community_id,
                'Host'::text as role
            from event_host eh
            join event e using (event_id)
            join "group" g using (group_id)
            where eh.user_id = p_user_id
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.starts_at > now()
            and g.active = true
            and g.deleted = false
        ),
        -- Collect event-level speaker events.
        event_speaker_events as (
            select
                e.event_id,
                e.group_id,
                e.starts_at,
                g.community_id,
                'Speaker'::text as role
            from event_speaker es
            join event e using (event_id)
            join "group" g using (group_id)
            where es.user_id = p_user_id
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.starts_at > now()
            and g.active = true
            and g.deleted = false
        ),
        -- Collect session-level speaker events.
        session_speaker_events as (
            select
                e.event_id,
                e.group_id,
                e.starts_at,
                g.community_id,
                'Speaker'::text as role
            from session_speaker ss
            join session s using (session_id)
            join event e using (event_id)
            join "group" g using (group_id)
            where ss.user_id = p_user_id
            and e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.starts_at > now()
            and g.active = true
            and g.deleted = false
        ),
        -- Combine all user roles by event.
        participant_roles as (
            select community_id, event_id, group_id, role, starts_at
            from attendee_events
            union all
            select community_id, event_id, group_id, role, starts_at
            from host_events
            union all
            select community_id, event_id, group_id, role, starts_at
            from event_speaker_events
            union all
            select community_id, event_id, group_id, role, starts_at
            from session_speaker_events
        ),
        -- Deduplicate role rows for the same event.
        unique_roles as (
            select distinct
                pr.community_id,
                pr.event_id,
                pr.group_id,
                pr.role,
                pr.starts_at
            from participant_roles pr
        ),
        -- Aggregate roles per event.
        event_rows as (
            select
                ur.community_id,
                ur.event_id,
                ur.group_id,
                array_agg(ur.role order by ur.role asc) as roles,
                ur.starts_at
            from unique_roles ur
            group by ur.community_id, ur.event_id, ur.group_id, ur.starts_at
        ),
        -- Select the requested page.
        event_rows_page as (
            select
                er.community_id,
                er.event_id,
                er.group_id,
                er.roles,
                er.starts_at
            from event_rows er
            order by er.starts_at asc, er.event_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count total events before pagination.
        totals as (
            select count(*)::int as total
            from event_rows
        ),
        -- Render paginated events to JSON.
        events_json as (
            select coalesce(
                json_agg(
                    json_build_object(
                        'event',
                        get_event_summary(
                            event_rows_page.community_id,
                            event_rows_page.group_id,
                            event_rows_page.event_id
                        ),
                        'roles',
                        event_rows_page.roles
                    )
                    order by event_rows_page.starts_at asc, event_rows_page.event_id asc
                ),
                '[]'::json
            ) as events
            from event_rows_page
        )
    -- Build final payload.
    select json_build_object(
        'events',
        events_json.events,
        'total',
        totals.total
    )
    from events_json, totals;
$$ language sql;

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
                ea.registration_answers,
                case
                    when ea.status = 'registration-questions-pending'
                        and pending_purchase.event_purchase_id is not null then 'Payment pending'
                    when ea.status = 'registration-questions-pending' then 'Registration pending'
                    else 'Attendee'
                end as role,
                ea.status = 'registration-questions-pending'
                    and pending_purchase.event_purchase_id is not null as pending_payment,
                ea.status = 'registration-questions-pending'
                    and pending_purchase.event_purchase_id is null as registration_questions_pending,
                case
                    when ea.status = 'registration-questions-pending' then pending_purchase.provider_checkout_url
                    else null
                end as resume_checkout_url
            from event_attendee ea
            join event e using (event_id)
            join "group" g using (group_id)
            left join lateral (
                select
                    ep.event_purchase_id,
                    ep.provider_checkout_url
                from event_purchase ep
                where ep.event_id = ea.event_id
                and ep.user_id = ea.user_id
                and ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
                order by ep.created_at desc, ep.event_purchase_id desc
                limit 1
            ) pending_purchase on true
            where ea.user_id = p_user_id
            and ea.status in ('confirmed', 'registration-questions-pending')
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
                null::jsonb as registration_answers,
                'Host'::text as role,
                false as pending_payment,
                false as registration_questions_pending,
                null::text as resume_checkout_url
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
                null::jsonb as registration_answers,
                'Speaker'::text as role,
                false as pending_payment,
                false as registration_questions_pending,
                null::text as resume_checkout_url
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
                null::jsonb as registration_answers,
                'Speaker'::text as role,
                false as pending_payment,
                false as registration_questions_pending,
                null::text as resume_checkout_url
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
            select
                community_id,
                event_id,
                group_id,
                pending_payment,
                registration_answers,
                registration_questions_pending,
                resume_checkout_url,
                role,
                starts_at
            from attendee_events
            union all
            select
                community_id,
                event_id,
                group_id,
                pending_payment,
                registration_answers,
                registration_questions_pending,
                resume_checkout_url,
                role,
                starts_at
            from host_events
            union all
            select
                community_id,
                event_id,
                group_id,
                pending_payment,
                registration_answers,
                registration_questions_pending,
                resume_checkout_url,
                role,
                starts_at
            from event_speaker_events
            union all
            select
                community_id,
                event_id,
                group_id,
                pending_payment,
                registration_answers,
                registration_questions_pending,
                resume_checkout_url,
                role,
                starts_at
            from session_speaker_events
        ),
        -- Deduplicate role rows for the same event.
        unique_roles as (
            select distinct
                pr.community_id,
                pr.event_id,
                pr.group_id,
                pr.pending_payment,
                pr.registration_answers,
                pr.registration_questions_pending,
                pr.resume_checkout_url,
                pr.starts_at,
                pr.role
            from participant_roles pr
        ),
        -- Aggregate roles per event.
        event_rows as (
            select
                ur.community_id,
                ur.event_id,
                ur.group_id,
                bool_or(ur.pending_payment) as pending_payment,
                (max(ur.registration_answers::text) filter (where ur.registration_answers is not null))::jsonb
                    as registration_answers,
                bool_or(ur.registration_questions_pending) as registration_questions_pending,
                max(ur.resume_checkout_url) as resume_checkout_url,
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
                er.pending_payment,
                er.registration_answers,
                er.registration_questions_pending,
                er.resume_checkout_url,
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
                        'can_cancel_attendance',
                        event_rows_page.roles = array['Attendee'::text]
                        and event_rows_page.registration_questions_pending = false
                        and not exists (
                            select 1
                            from event_purchase ep
                            where ep.event_id = event_rows_page.event_id
                            and ep.user_id = p_user_id
                            and ep.status in ('completed', 'refund-requested')
                            and ep.amount_minor > 0
                        ),
                        'can_complete_registration_questions',
                        event_rows_page.pending_payment = false
                        and (
                            event_rows_page.registration_questions_pending
                            or (
                                'Attendee' = any(event_rows_page.roles)
                                and
                                json_array_length(
                                    get_event_registration_questions(
                                        event_rows_page.community_id,
                                        event_rows_page.event_id
                                    )
                                ) > 0
                                and event_rows_page.starts_at > now()
                            )
                        ),
                        'event',
                        get_event_summary(
                            event_rows_page.community_id,
                            event_rows_page.group_id,
                            event_rows_page.event_id
                        ),
                        'pending_payment',
                        event_rows_page.pending_payment,
                        'registration_answers',
                        event_rows_page.registration_answers,
                        'registration_questions',
                        get_event_registration_questions(
                            event_rows_page.community_id,
                            event_rows_page.event_id
                        ),
                        'registration_questions_pending',
                        event_rows_page.registration_questions_pending,
                        'resume_checkout_url',
                        event_rows_page.resume_checkout_url,
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

-- Returns paginated upcoming events where the user participates.
create or replace function list_user_events(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Collect visible upcoming events once for all participation roles.
        visible_events as (
            select
                g.community_id,
                e.event_id,
                e.group_id,
                e.starts_at
            from event e
            join "group" g using (group_id)
            where e.canceled = false
            and e.deleted = false
            and e.published = true
            and e.starts_at > now()
            and g.active = true
            and g.deleted = false
        ),
        -- Collect user participation roles.
        role_rows as (
            -- Attendee
            select
                case
                    when ea.status = 'registration-questions-pending'
                        and pending_purchase.event_purchase_id is not null then 'pending-payment'
                    when ea.status = 'registration-questions-pending' then 'registration-questions-pending'
                    else 'attendee'
                end as attendance_status,
                ea.event_id,
                ea.registration_answers,
                'attendee'::text as role,
                case
                    when ea.status = 'registration-questions-pending' then pending_purchase.provider_checkout_url
                    else null
                end as resume_checkout_url
            from event_attendee ea
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

            union all

            -- Host
            select
                null::text as attendance_status,
                eh.event_id,
                null::jsonb as registration_answers,
                'host'::text as role,
                null::text as resume_checkout_url
            from event_host eh
            where eh.user_id = p_user_id

            union all

            -- Event speaker
            select
                null::text as attendance_status,
                es.event_id,
                null::jsonb as registration_answers,
                'speaker'::text as role,
                null::text as resume_checkout_url
            from event_speaker es
            where es.user_id = p_user_id

            union all

            -- Session speaker
            select
                null::text as attendance_status,
                s.event_id,
                null::jsonb as registration_answers,
                'speaker'::text as role,
                null::text as resume_checkout_url
            from session_speaker ss
            join session s using (session_id)
            where ss.user_id = p_user_id
        ),
        -- Aggregate roles per event.
        event_rows as (
            select
                max(rr.attendance_status) as attendance_status,
                ve.community_id,
                ve.event_id,
                ve.group_id,
                (max(rr.registration_answers::text) filter (where rr.registration_answers is not null))::jsonb
                    as registration_answers,
                max(rr.resume_checkout_url) as resume_checkout_url,
                array_agg(distinct rr.role order by rr.role asc) as roles,
                ve.starts_at
            from visible_events ve
            join role_rows rr using (event_id)
            group by ve.community_id, ve.event_id, ve.group_id, ve.starts_at
        ),
        -- Select the requested page.
        event_rows_page as (
            select
                er.attendance_status,
                er.community_id,
                er.event_id,
                er.group_id,
                er.registration_answers,
                er.resume_checkout_url,
                er.roles,
                er.starts_at
            from event_rows er
            order by er.starts_at asc, er.event_id asc
            offset (p_filters->>'offset')::int
            limit (p_filters->>'limit')::int
        )
    -- Build final payload.
    select json_build_object(
        'events',
        (
            select coalesce(
                json_agg(
                    json_build_object(
                        'event',
                        get_event_summary(
                            erp.community_id,
                            erp.group_id,
                            erp.event_id
                        ),
                        'has_paid_purchase',
                        exists (
                            select 1
                            from event_purchase ep
                            where ep.event_id = erp.event_id
                            and ep.user_id = p_user_id
                            and ep.status in ('completed', 'refund-requested')
                            and ep.amount_minor > 0
                        ),
                        'registration_questions',
                        rq.registration_questions,
                        'roles',
                        erp.roles,
                        'attendance_status',
                        erp.attendance_status,
                        'registration_answers',
                        erp.registration_answers,
                        'resume_checkout_url',
                        erp.resume_checkout_url
                    )
                    order by erp.starts_at asc, erp.event_id asc
                ),
                '[]'::json
            )
            from event_rows_page erp
            cross join lateral (
                select get_event_registration_questions(erp.community_id, erp.event_id)
                    as registration_questions
            ) rq
        ),
        'total',
        (select count(*)::int from event_rows)
    );
$$ language sql;

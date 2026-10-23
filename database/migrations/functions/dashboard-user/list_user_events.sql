-- Returns paginated upcoming events where the user attends, hosts, organizes, speaks, or has actionable admission state.
create or replace function list_user_events(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Normalize common list filters
        filters as (
            select
                f.limit_value,
                f.offset_value
            from parse_search_filters(p_filters) f
        ),
        -- Collect visible upcoming events once for all participation roles
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
        -- Collect user participation roles
        role_rows as (
            -- Attendee
            select
                pending_purchase.admission_offer_id,
                pending_purchase.admission_offer_source,
                pending_purchase.admission_offer_status,
                pending_purchase.amount_minor,
                pending_purchase.currency_code,
                case
                    -- Report a questionnaire reservation backed by a live checkout
                    when ea.status = 'registration-questions-pending'
                        and pending_purchase.event_purchase_id is not null then 'pending-payment'
                    -- Report a questionnaire reservation waiting on answers
                    when ea.status = 'registration-questions-pending' then 'registration-questions-pending'
                    -- Report a confirmed attendee
                    else 'attendee'
                end as enrollment_status,
                ea.event_id,
                pending_purchase.event_ticket_type_id,
                ea.manually_invited,
                pending_purchase.offer_expires_at,
                ea.registration_answers,
                case
                    -- Resume the live checkout of a questionnaire reservation
                    when ea.status = 'registration-questions-pending' then pending_purchase.provider_checkout_url
                    -- Leave confirmed attendees without a checkout to resume
                    else null
                end as resume_checkout_url,
                case
                    -- Report a checkout that claims an admission offer as an offer
                    when pending_purchase.admission_offer_id is not null then 'offer'
                    -- Leave a direct checkout to the active direct checkout branch
                    when ea.status = 'registration-questions-pending'
                        and pending_purchase.event_purchase_id is not null then null
                    -- Report the attendee role
                    else 'attendee'
                end as role,
                pending_purchase.ticket_title
            from event_attendee ea
            left join lateral (
                select
                    ao.admission_offer_id,
                    ao.source as admission_offer_source,
                    ao.status as admission_offer_status,
                    ep.amount_minor,
                    ep.currency_code,
                    ep.event_purchase_id,
                    ep.event_ticket_type_id,
                    ao.expires_at as offer_expires_at,
                    ep.provider_checkout_url,
                    ep.ticket_title
                from event_purchase ep
                left join admission_offer ao using (admission_offer_id)
                where ep.event_id = ea.event_id
                and ep.user_id = ea.user_id
                and ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
                order by ep.created_at desc, ep.event_purchase_id desc
                limit 1
            ) pending_purchase on true
            where ea.user_id = p_user_id
            and ea.status in ('confirmed', 'registration-questions-pending')
            and not (
                ea.status = 'registration-questions-pending'
                and ea.manually_invited = false
                and pending_purchase.event_purchase_id is null
                and exists (
                    select 1
                    from event_purchase expired_purchase
                    where expired_purchase.event_id = ea.event_id
                    and expired_purchase.user_id = ea.user_id
                    and expired_purchase.status = 'pending'
                    and expired_purchase.hold_expires_at <= current_timestamp
                )
            )

            union all

            -- Active direct checkout
            select
                null::uuid as admission_offer_id,
                null::text as admission_offer_source,
                null::text as admission_offer_status,
                ep.amount_minor,
                ep.currency_code,
                'pending-payment'::text as enrollment_status,
                ep.event_id,
                ep.event_ticket_type_id,
                false as manually_invited,
                null::timestamptz as offer_expires_at,
                null::jsonb as registration_answers,
                ep.provider_checkout_url as resume_checkout_url,
                null::text as role,
                ep.ticket_title
            from event_purchase ep
            where ep.user_id = p_user_id
            and ep.admission_offer_id is null
            and ep.status = 'pending'
            and ep.hold_expires_at > current_timestamp

            union all

            -- Active admission offer
            select
                ao.admission_offer_id,
                ao.source as admission_offer_source,
                ao.status as admission_offer_status,
                display_price.amount_minor,
                display_price.currency_code,
                'invitation-approved' as enrollment_status,
                ao.event_id,
                ao.event_ticket_type_id,
                ao.source = 'organizer_invitation' as manually_invited,
                ao.expires_at as offer_expires_at,
                ea.registration_answers,
                pending_purchase.provider_checkout_url as resume_checkout_url,
                'offer'::text as role,
                coalesce(ao.ticket_title, ett.title) as ticket_title
            from admission_offer ao
            join event e using (event_id)
            left join event_attendee ea
                on ea.event_id = ao.event_id
                and ea.user_id = ao.user_id
            join event_ticket_type ett using (event_ticket_type_id)
            cross join lateral admission_offer_display_price(ao, e) display_price
            left join lateral (
                select ep.provider_checkout_url
                from event_purchase ep
                where ep.admission_offer_id = ao.admission_offer_id
                and ep.status = 'pending'
                and ep.hold_expires_at > current_timestamp
                order by ep.created_at desc, ep.event_purchase_id desc
                limit 1
            ) pending_purchase on true
            where ao.user_id = p_user_id
            and admission_offer_is_claimable(ao)

            union all

            -- Host, organizer and speaker roles
            select
                null::uuid as admission_offer_id,
                null::text as admission_offer_source,
                null::text as admission_offer_status,
                null::bigint as amount_minor,
                null::text as currency_code,
                null::text as enrollment_status,
                r.event_id,
                null::uuid as event_ticket_type_id,
                false as manually_invited,
                null::timestamptz as offer_expires_at,
                null::jsonb as registration_answers,
                null::text as resume_checkout_url,
                r.role,
                null::text as ticket_title
            from (
                -- Event host
                select eh.event_id, 'host'::text as role
                from event_host eh
                where eh.user_id = p_user_id

                union all

                -- Event organizer
                select eo.event_id, 'organizer'
                from event_organizer eo
                where eo.user_id = p_user_id

                union all

                -- Event speaker
                select es.event_id, 'speaker'
                from event_speaker es
                where es.user_id = p_user_id

                union all

                -- Session speaker
                select s.event_id, 'speaker'
                from session_speaker ss
                join session s using (session_id)
                where ss.user_id = p_user_id
            ) r
        ),
        -- Aggregate roles per event
        event_rows as (
            select
                (array_agg(rr.admission_offer_id) filter (
                    where rr.admission_offer_id is not null
                ))[1] as admission_offer_id,
                max(rr.admission_offer_source) as admission_offer_source,
                max(rr.admission_offer_status) as admission_offer_status,
                max(rr.amount_minor) as amount_minor,
                ve.community_id,
                max(rr.currency_code) as currency_code,
                max(rr.enrollment_status) as enrollment_status,
                ve.event_id,
                (array_agg(rr.event_ticket_type_id) filter (
                    where rr.event_ticket_type_id is not null
                ))[1] as event_ticket_type_id,
                ve.group_id,
                bool_or(rr.manually_invited) as manually_invited,
                max(rr.offer_expires_at) as offer_expires_at,
                (max(rr.registration_answers::text) filter (where rr.registration_answers is not null))::jsonb
                    as registration_answers,
                max(rr.resume_checkout_url) as resume_checkout_url,
                coalesce(
                    array_agg(distinct rr.role order by rr.role asc) filter (
                        where rr.role is not null
                    ),
                    '{}'::text[]
                ) as roles,
                ve.starts_at,
                max(rr.ticket_title) as ticket_title
            from visible_events ve
            join role_rows rr using (event_id)
            group by ve.community_id, ve.event_id, ve.group_id, ve.starts_at
        ),
        -- Select the requested page
        event_rows_page as (
            select
                er.admission_offer_id,
                er.admission_offer_source,
                er.admission_offer_status,
                er.amount_minor,
                er.community_id,
                er.currency_code,
                er.enrollment_status,
                er.event_id,
                er.event_ticket_type_id,
                er.group_id,
                er.manually_invited,
                er.offer_expires_at,
                er.registration_answers,
                er.resume_checkout_url,
                er.roles,
                er.starts_at,
                er.ticket_title
            from event_rows er
            order by er.starts_at asc, er.event_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        )
    -- Build final payload
    select json_build_object(
        'events',
        (
            select coalesce(
                json_agg(
                    (
                        jsonb_build_object(
                            'event',
                            get_event_summary(
                                erp.community_id,
                                erp.group_id,
                                erp.event_id
                            ),
                            'enrollment_status',
                            erp.enrollment_status,
                            'has_paid_purchase',
                            exists (
                                select 1
                                from event_purchase ep
                                where ep.event_id = erp.event_id
                                and ep.user_id = p_user_id
                                and ep.status in ('completed', 'refund-requested')
                                and ep.amount_minor > 0
                            ),
                            'registration_answers',
                            erp.registration_answers,
                            'registration_questions',
                            rq.registration_questions,
                            'roles',
                            erp.roles
                        )
                        || jsonb_strip_nulls(jsonb_build_object(
                            'admission_offer_id',
                            erp.admission_offer_id,
                            'admission_offer_source',
                            erp.admission_offer_source,
                            'admission_offer_status',
                            erp.admission_offer_status,
                            'amount_minor',
                            erp.amount_minor,
                            'currency_code',
                            erp.currency_code,
                            'event_ticket_type_id',
                            erp.event_ticket_type_id,
                            'external_payment',
                            ext.external_payment,
                            'offer_expires_at',
                            epoch_seconds(erp.offer_expires_at),
                            'refund_rejection_reason',
                            en.refund_rejection_reason,
                            'refund_request_status',
                            en.refund_request_status,
                            'resume_checkout_url',
                            case
                                -- Resume provider checkout unless an external payment is pending
                                when ext.external_payment is null then erp.resume_checkout_url
                            end,
                            'ticket_title',
                            erp.ticket_title
                        ))
                        || case
                            -- Flag events the user was manually invited to
                            when erp.manually_invited then jsonb_build_object('manually_invited', true)
                            -- Omit the flag otherwise
                            else '{}'::jsonb
                        end
                    )
                    order by erp.starts_at asc, erp.event_id asc
                ),
                '[]'::json
            )
            from event_rows_page erp
            -- Read the refund state from the purchase that represents the enrollment
            cross join lateral event_user_enrollment(erp.event_id, p_user_id) en
            -- Describe the external payment owed by the latest live external checkout
            left join lateral (
                select event_purchase_external_payment_json(e, ep) as external_payment
                from event_purchase ep
                join event e using (event_id)
                where ep.event_id = erp.event_id
                and ep.user_id = p_user_id
                and ep.status = 'pending'
                and ep.charge_model = 'external'
                and ep.hold_expires_at > current_timestamp
                order by ep.created_at desc, ep.event_purchase_id desc
                limit 1
            ) ext on true
            -- Load the registration questions shown with the event
            cross join lateral (
                select get_event_registration_questions(erp.community_id, erp.event_id)
                    as registration_questions
            ) rq
        ),
        'total',
        (select count(*)::int from event_rows)
    );
$$ language sql stable;

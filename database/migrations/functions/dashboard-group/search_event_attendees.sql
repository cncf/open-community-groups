-- Returns paginated attendees for a group's event using provided filters.
create or replace function search_event_attendees(p_group_id uuid, p_event_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Parse filters for pagination
        filters as (
            select
                (p_filters->>'checked_in')::boolean as checked_in_value,
                (p_filters->>'limit')::int as limit_value,
                (p_filters->>'offset')::int as offset_value,
                case
                    when lower(p_filters->>'sort') in (
                        'created-at-asc',
                        'created-at-desc',
                        'name-asc',
                        'name-desc'
                    ) then lower(p_filters->>'sort')
                    else 'name-asc'
                end as sort_value,
                case
                    when lower(p_filters->>'status') in (
                        'all',
                        'attendance-canceled',
                        'checkout-pending',
                        'confirmed',
                        'current',
                        'history',
                        'invitation-canceled',
                        'invitation-declined',
                        'invitation-expired',
                        'invitation-pending',
                        'payment-pending',
                        'registration-pending'
                    ) then lower(p_filters->>'status')
                    else null
                end as status_value,
                case
                    when lower(p_filters->>'title') in ('missing', 'present')
                        then lower(p_filters->>'title')
                    else null
                end as title_value,
                nullif(btrim(p_filters->>'ts_query'), '') as ts_query_value
        ),
        -- Parse selected ticket type filters
        ticket_type_filter as (
            select
                count(*)::int as ticket_types_total,
                coalesce(array_agg(event_ticket_type_id), '{}') as selected_event_ticket_type_ids
            from (
                select value::uuid as event_ticket_type_id
                from jsonb_array_elements_text(
                    coalesce(p_filters->'event_ticket_type_ids', '[]'::jsonb)
                )
            ) input_ticket_types
        ),
        -- Prepare text search with prefix matching
        search_filter as (
            select
                ts_rewrite(
                    websearch_to_tsquery('simple', ts_query_value),
                    format('
                        select
                            to_tsquery(''simple'', lexeme),
                            to_tsquery(''simple'', lexeme || '':*'')
                        from unnest(tsvector_to_array(to_tsvector(''simple'', %L))) as lexeme
                        ', ts_query_value
                    )
                ) as ts_query
            from filters
            where ts_query_value is not null
        ),
        -- Normalize attendee and organizer-offer rows into one enrollment shape
        enrollment_candidates as (
            select
                null::uuid as admission_offer_id,
                null::text as admission_offer_source,
                null::text as admission_offer_status,
                ea.checked_in,
                ea.checked_in_at,
                ea.created_at,
                ea.event_id,
                null::uuid as event_ticket_type_id,
                ea.manually_invited,
                null::timestamptz as offer_expires_at,
                ea.registration_answers,
                0 as source_priority,
                case
                    when ea.status = 'invitation-rejected' then 'invitation-declined'
                    when ea.status = 'registration-questions-pending' then 'registration-pending'
                    else ea.status
                end as enrollment_status,
                null::text as ticket_title,
                ea.user_id
            from event_attendee ea
            where ea.status in (
                'attendance-canceled',
                'confirmed',
                'invitation-canceled',
                'invitation-pending',
                'invitation-rejected',
                'registration-questions-pending'
            )

            union all

            -- Include external holds without a questionnaire or offer row
            select
                null::uuid as admission_offer_id,
                null::text as admission_offer_source,
                null::text as admission_offer_status,
                false as checked_in,
                null::timestamptz as checked_in_at,
                ep.created_at,
                ep.event_id,
                ep.event_ticket_type_id,
                false as manually_invited,
                null::timestamptz as offer_expires_at,
                null::jsonb as registration_answers,
                0 as source_priority,
                'registration-pending' as enrollment_status,
                ep.ticket_title,
                ep.user_id
            from event_purchase ep
            where ep.status = 'pending'
            and ep.charge_model = 'external'
            and not exists (
                select 1
                from event_attendee ea
                where ea.event_id = ep.event_id
                and ea.user_id = ep.user_id
                and ea.status in (
                    'attendance-canceled',
                    'confirmed',
                    'invitation-canceled',
                    'invitation-pending',
                    'invitation-rejected',
                    'registration-questions-pending'
                )
            )
            and not exists (
                select 1
                from admission_offer ao
                where ao.event_id = ep.event_id
                and ao.user_id = ep.user_id
                and ao.source = 'organizer_invitation'
                and ao.status in (
                    'canceled',
                    'checkout_pending',
                    'declined',
                    'expired',
                    'pending'
                )
            )

            union all

            select
                ao.admission_offer_id,
                ao.source as admission_offer_source,
                ao.status as admission_offer_status,
                false as checked_in,
                null::timestamptz as checked_in_at,
                ao.created_at,
                ao.event_id,
                ao.event_ticket_type_id,
                true as manually_invited,
                ao.expires_at as offer_expires_at,
                null::jsonb as registration_answers,
                case
                    when ao.status in ('checkout_pending', 'pending') then 1
                    else 0
                end as source_priority,
                case
                    when ao.status = 'canceled' then 'invitation-canceled'
                    when ao.status = 'checkout_pending' then 'checkout-pending'
                    when ao.status = 'declined' then 'invitation-declined'
                    when ao.status = 'expired' then 'invitation-expired'
                    else 'invitation-pending'
                end as enrollment_status,
                coalesce(ao.ticket_title, ett.title) as ticket_title,
                ao.user_id
            from admission_offer ao
            join event_ticket_type ett using (event_ticket_type_id)
            where ao.source = 'organizer_invitation'
            and ao.status in ('canceled', 'checkout_pending', 'declined', 'expired', 'pending')
        ),
        -- Keep the latest attendee or organizer-offer state for each user
        enrollment_rows as (
            select
                admission_offer_id,
                admission_offer_source,
                admission_offer_status,
                checked_in,
                checked_in_at,
                created_at,
                event_id,
                event_ticket_type_id,
                enrollment_status,
                manually_invited,
                offer_expires_at,
                registration_answers,
                ticket_title,
                user_id
            from (
                select
                    enrollment_candidates.*,
                    row_number() over (
                        partition by event_id, user_id
                        order by source_priority desc, created_at desc
                    ) as enrollment_rank
                from enrollment_candidates
            ) ranked_enrollment
            where enrollment_rank = 1
        ),
        -- Select visible attendee and invitation rows
        base_attendees as (
            select
                er.admission_offer_id,
                er.admission_offer_source,
                er.admission_offer_status,
                er.checked_in,
                extract(epoch from er.created_at)::bigint as created_at,
                er.created_at as created_at_sort,
                u.email,
                case
                    when ep.purchase_status = 'pending'
                        and ep.charge_model = 'external'
                        and ep.hold_expires_at > current_timestamp
                        and er.enrollment_status is distinct from 'confirmed'
                        then 'payment-pending'
                    when er.enrollment_status = 'registration-pending'
                        and ep.purchase_status = 'pending' then 'checkout-pending'
                    else er.enrollment_status
                end as enrollment_status,
                er.manually_invited,
                er.registration_answers,
                e.canceled as event_canceled,
                u.user_id,
                u.username,

                extract(epoch from er.checked_in_at)::bigint as checked_in_at,
                ep.amount_minor,
                ep.charge_model,
                extract(epoch from ep.completed_at)::bigint as completed_at,
                u.company,
                ep.currency_code,
                ep.discount_code,
                case
                    when ep.charge_model = 'external'
                    then extract(epoch from ep.hold_expires_at)::bigint
                end as external_payment_deadline,
                ep.external_payment_details,
                marked_by.username as external_payment_marked_by,
                case
                    when ep.charge_model = 'external' then ep.event_purchase_id
                end as external_payment_reference,
                ep.event_purchase_id,
                coalesce(
                    ep.charge_model = 'external' and ep.purchase_status = 'completed',
                    false
                ) as externally_paid,
                coalesce(ep.event_ticket_type_id, er.event_ticket_type_id)
                    as event_ticket_type_id,
                extract(epoch from er.offer_expires_at)::bigint as offer_expires_at,
                coalesce(ep.ticket_title, er.ticket_title) as ticket_title,
                u.bio,
                u.bluesky_url,
                u.name,
                u.facebook_url,
                u.github_url,
                u.linkedin_url,
                u.photo_url,
                get_public_user_provider(u.provider) as provider,
                case
                    when ep.purchase_status = 'pending'
                        and e.canceled
                        and (
                            ep.hold_expires_at > current_timestamp
                            or ep.provider_checkout_session_id is not null
                        ) then 'awaiting-checkout'
                    when epr.status = 'finalized' or ep.purchase_status = 'refunded' then 'refunded'
                    when epr.status in ('processing', 'provider-succeeded') then 'processing'
                    when epr.status = 'provider-pending'
                        and epr.attempt_count >= 10 then 'retryable-failure'
                    when epr.status = 'provider-pending'
                        and epr.provider_refund_id is not null then 'processing'
                    when epr.status = 'provider-pending' then 'queued'
                    when epr.status = 'provider-failed'
                        and epr.terminal_failure then 'recovery-required'
                    when epr.status = 'provider-failed'
                        and epr.attempt_count >= 10 then 'retryable-failure'
                    when epr.status = 'provider-failed' then 'queued'
                    else null
                end as refund_progress,
                err.status as refund_request_status,
                u.twitter_url,
                u.tsdoc,
                u.title,
                u.website_url,

                (
                    er.enrollment_status in ('confirmed', 'registration-pending')
                    and er.admission_offer_id is null
                    and u.email_verified = true
                    and coalesce(u.optional_notifications_enabled, true) = true
                    and pending_ep.event_purchase_id is null
                ) as can_receive_attendee_email
            from enrollment_rows er
            join event e on e.event_id = er.event_id
            join "user" u on u.user_id = er.user_id
            left join lateral (
                select
                    event_purchase_id,
                    amount_minor,
                    charge_model,
                    currency_code,
                    event_ticket_type_id,
                    status as purchase_status,
                    ticket_title,

                    completed_at,
                    discount_code,
                    external_payment_details,
                    external_payment_marked_by_user_id,
                    hold_expires_at,
                    provider_checkout_session_id
                from event_purchase
                where event_id = er.event_id
                and user_id = er.user_id
                and status in (
                    'completed',
                    'pending',
                    'refund-pending',
                    'refund-recovery-pending',
                    'refund-requested',
                    'refunded'
                )
                order by created_at desc, event_purchase_id desc
                limit 1
            ) ep on true
            left join lateral (
                select status
                from event_refund_request
                where event_purchase_id = ep.event_purchase_id
                order by created_at desc, event_refund_request_id desc
                limit 1
            ) err on true
            left join event_purchase_refund epr on epr.event_purchase_id = ep.event_purchase_id
            left join lateral (
                select event_purchase_id
                from event_purchase
                where event_id = er.event_id
                and user_id = er.user_id
                and status = 'pending'
                and hold_expires_at > current_timestamp
                order by created_at desc, event_purchase_id desc
                limit 1
            ) pending_ep on true
            left join "user" marked_by
                on marked_by.user_id = ep.external_payment_marked_by_user_id
            where e.group_id = p_group_id
            and er.event_id = p_event_id
        ),
        -- Apply table filters while retaining internal search data
        filtered_attendees as (
            select *
            from base_attendees
            where (
                not exists (select 1 from search_filter)
                or exists (
                    select 1
                    from search_filter
                    where search_filter.ts_query @@ base_attendees.tsdoc
                )
            )
            and (
                coalesce(
                    (select status_value from filters),
                    case when event_canceled then 'all' else 'current' end
                ) = 'all'
                or (
                    coalesce(
                        (select status_value from filters),
                        case when event_canceled then 'all' else 'current' end
                    ) = 'current'
                    and enrollment_status in (
                        'checkout-pending',
                        'confirmed',
                        'invitation-pending',
                        'payment-pending',
                        'registration-pending'
                    )
                )
                or (
                    (select status_value from filters) = 'history'
                    and enrollment_status in (
                        'attendance-canceled',
                        'invitation-canceled',
                        'invitation-declined',
                        'invitation-expired'
                    )
                )
                or (select status_value from filters) = enrollment_status
            )
            and (
                (select checked_in_value from filters) is null
                or (
                    enrollment_status = 'confirmed'
                    and checked_in = (select checked_in_value from filters)
                )
            )
            and (
                (select title_value from filters) is null
                or ((select title_value from filters) = 'present' and title is not null)
                or ((select title_value from filters) = 'missing' and title is null)
            )
            and (
                (select ticket_types_total from ticket_type_filter) = 0
                or event_ticket_type_id in (
                    select unnest(selected_event_ticket_type_ids)
                    from ticket_type_filter
                )
            )
        ),
        -- Apply pagination and project public attendee fields
        attendees as (
            select
                can_receive_attendee_email,
                checked_in,
                created_at,
                email,
                enrollment_status,
                manually_invited,
                json_strip_nulls(json_build_object(
                    'user_id', user_id,
                    'username', username,

                    'bio', bio,
                    'bluesky_url', bluesky_url,
                    'company', company,
                    'facebook_url', facebook_url,
                    'github_url', github_url,
                    'linkedin_url', linkedin_url,
                    'name', name,
                    'photo_url', photo_url,
                    'provider', provider,
                    'title', title,
                    'twitter_url', twitter_url,
                    'website_url', website_url
                )) as "user",

                admission_offer_id,
                admission_offer_source,
                admission_offer_status,
                amount_minor,
                charge_model,
                checked_in_at,
                completed_at,
                currency_code,
                discount_code,
                event_purchase_id,
                event_ticket_type_id,
                external_payment_deadline,
                external_payment_details,
                external_payment_marked_by,
                external_payment_reference,
                externally_paid,
                offer_expires_at,
                refund_progress,
                refund_request_status,
                registration_answers,
                ticket_title
            from filtered_attendees
            cross join filters f
            order by
                case when f.sort_value = 'name-asc'
                    then coalesce(lower(name), lower(username))
                end asc nulls last,
                case when f.sort_value = 'name-desc'
                    then coalesce(lower(name), lower(username))
                end desc nulls last,
                case when f.sort_value = 'created-at-asc'
                    then created_at_sort
                end asc nulls last,
                case when f.sort_value = 'created-at-desc'
                    then created_at_sort
                end desc nulls last,
                user_id asc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        ),
        -- Count filtered rows and event-wide eligible notification recipients
        totals as (
            select
                (
                    select count(*)::int
                    from base_attendees
                    where can_receive_attendee_email = true
                ) as all_attendees_email_recipient_total,
                count(*)::int as total
            from filtered_attendees
        ),
        -- Render attendees as JSON
        attendees_json as (
            select coalesce(
                jsonb_agg(
                    case
                        when refund_progress is null
                            then row_to_json(attendees)::jsonb - 'refund_progress'
                        else row_to_json(attendees)::jsonb
                    end
                ),
                '[]'::jsonb
            ) as attendees
            from attendees
        )
    -- Build final payload
    select json_build_object(
        'all_attendees_email_recipient_total', totals.all_attendees_email_recipient_total,
        'attendees', attendees_json.attendees,
        'total', totals.total
    )
    from attendees_json, totals;
$$ language sql;

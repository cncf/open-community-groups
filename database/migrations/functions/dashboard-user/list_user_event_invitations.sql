-- Returns all active admission offers owned by a user.
create or replace function list_user_event_invitations(p_user_id uuid)
returns json as $$
    select coalesce(
        json_agg(json_strip_nulls(row_to_json(invitation))),
        '[]'::json
    )
    from (
        select
            ao.admission_offer_id,
            ao.source as admission_offer_source,
            ao.status as admission_offer_status,
            c.display_name as community_display_name,
            c.name as community_name,
            extract(epoch from ao.created_at)::bigint as created_at,
            e.event_id,
            e.name as event_name,
            ao.event_ticket_type_id,
            extract(epoch from ao.expires_at)::bigint as expires_at,
            g.name as group_name,
            coalesce(
                is_event_simple_rsvp(e.event_id)
                and ett.availability = 'public'
                and coalesce(ao.amount_minor, current_price.amount_minor) = 0,
                false
            ) as is_simple_rsvp,
            coalesce(ao.ticket_title, ett.title) as ticket_title,
            e.timezone,

            coalesce(ao.amount_minor, current_price.amount_minor) as amount_minor,
            case
                when coalesce(ao.amount_minor, current_price.amount_minor) > 0
                     or coalesce(ao.discount_amount_minor, 0) > 0
                    then coalesce(ao.currency_code, e.payment_currency_code)
            end as currency_code,
            case
                when ao.source = 'approval'
                    then coalesce(
                        invitation_request.registration_answers,
                        ea.registration_answers
                    )
                else coalesce(
                    ea.registration_answers,
                    invitation_request.registration_answers
                )
            end as registration_answers,
            get_event_registration_questions(c.community_id, e.event_id)
                as registration_questions,
            pending_purchase.provider_checkout_url as resume_checkout_url,
            extract(epoch from e.starts_at)::bigint as starts_at
        from admission_offer ao
        join event e using (event_id)
        join "group" g using (group_id)
        join community c using (community_id)
        join event_ticket_type ett using (event_ticket_type_id)
        left join event_attendee ea
            on ea.event_id = ao.event_id
            and ea.user_id = ao.user_id
        left join lateral (
            select eir.registration_answers
            from event_invitation_request eir
            where eir.event_id = ao.event_id
            and eir.user_id = ao.user_id
            order by eir.created_at desc
            limit 1
        ) invitation_request on true
        left join lateral (
            select etpw.amount_minor
            from event_ticket_price_window etpw
            where etpw.event_ticket_type_id = ao.event_ticket_type_id
            and (etpw.starts_at is null or etpw.starts_at <= current_timestamp)
            and (etpw.ends_at is null or etpw.ends_at >= current_timestamp)
            order by
                etpw.starts_at desc nulls last,
                etpw.event_ticket_price_window_id
            limit 1
        ) current_price on true
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
        and ao.status in ('checkout_pending', 'pending')
        and ao.expires_at > current_timestamp
        and not exists (
            select 1
            from event_purchase ep
            where ep.admission_offer_id = ao.admission_offer_id
            and ep.status in (
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )
        )
        and g.active = true
        and e.deleted = false
        and e.published = true
        and e.canceled = false
        and (
            coalesce(e.ends_at, e.starts_at) is null
            or coalesce(e.ends_at, e.starts_at) >= current_timestamp
        )
        order by ao.created_at desc
    ) invitation;
$$ language sql;

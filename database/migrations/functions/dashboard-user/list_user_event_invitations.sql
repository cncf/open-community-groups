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
            epoch_seconds(ao.created_at) as created_at,
            e.event_id,
            e.name as event_name,
            ao.event_ticket_type_id,
            epoch_seconds(ao.expires_at) as expires_at,
            g.name as group_name,
            coalesce(
                is_event_simple_rsvp(e.event_id)
                and ett.availability = 'public'
                and display_price.amount_minor = 0,
                false
            ) as is_simple_rsvp,
            coalesce(ao.ticket_title, ett.title) as ticket_title,
            e.timezone,

            display_price.amount_minor,
            display_price.currency_code,
            case
                -- Prefer the answers submitted with the approval request
                when ao.source = 'approval'
                    then coalesce(
                        invitation_request.registration_answers,
                        ea.registration_answers
                    )
                -- Prefer the answers stored on the attendee row
                else coalesce(
                    ea.registration_answers,
                    invitation_request.registration_answers
                )
            end as registration_answers,
            get_event_registration_questions(c.community_id, e.event_id)
                as registration_questions,
            case
                -- Resume provider checkout for non-external pending purchases
                when (pending_purchase.purchase).charge_model is distinct from 'external'
                then (pending_purchase.purchase).provider_checkout_url
            end as resume_checkout_url,
            epoch_seconds(e.starts_at) as starts_at,

            case
                -- Describe the external payment owed by a pending purchase
                when (pending_purchase.purchase).charge_model = 'external'
                then event_purchase_external_payment_json(e, pending_purchase.purchase)
            end as external_payment
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
        cross join lateral admission_offer_display_price(ao, e) display_price
        left join lateral (
            select ep as purchase
            from event_purchase ep
            where ep.admission_offer_id = ao.admission_offer_id
            and ep.status = 'pending'
            and ep.hold_expires_at > current_timestamp
            order by ep.created_at desc, ep.event_purchase_id desc
            limit 1
        ) pending_purchase on true
        where ao.user_id = p_user_id
        and admission_offer_is_claimable(ao)
        and event_accepts_enrollment(e, g)
        order by ao.created_at desc
    ) invitation;
$$ language sql stable;

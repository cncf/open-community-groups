-- Cancels active enrollment reservations and clears queues for an event.
create or replace function close_event_enrollment(
    p_actor_user_id uuid,
    p_event_id uuid
)
returns uuid[] as $$
declare
    v_admission_offer record;
    v_canceled_user_ids uuid[] := array[]::uuid[];
    v_community_id uuid;
    v_event_name text;
    v_event_purchase record;
    v_group_id uuid;
    v_group_name text;
    v_theme jsonb;
    v_user_id uuid;
begin
    -- Lock the event before every tier and enrollment row closed below
    select
        g.community_id,
        e.name,
        e.group_id,
        g.name
    into
        v_community_id,
        v_event_name,
        v_group_id,
        v_group_name
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    for update of e;

    if not found then
        raise exception 'event not found';
    end if;

    -- Load shared presentation data for transactional cancellation notifications
    select s.theme
    into v_theme
    from site s
    limit 1;

    -- Lock ticket tiers before event-user and enrollment row locks
    perform 1
    from event_ticket_type ett
    where ett.event_id = p_event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Acquire every affected event-user lock in stable order
    for v_user_id in
        select affected_user.user_id
        from (
            select ao.user_id
            from admission_offer ao
            where ao.event_id = p_event_id
            and ao.status in ('checkout_pending', 'pending')

            union

            select ea.user_id
            from event_attendee ea
            where ea.event_id = p_event_id
            and ea.status in (
                'confirmed',
                'invitation-pending',
                'registration-questions-pending'
            )

            union

            select eir.user_id
            from event_invitation_request eir
            where eir.event_id = p_event_id
            and eir.status = 'pending'

            union

            select ep.user_id
            from event_purchase ep
            where ep.event_id = p_event_id
            and ep.status in (
                'completed',
                'pending',
                'refund-pending',
                'refund-recovery-pending',
                'refund-requested'
            )

            union

            select ew.user_id
            from event_waitlist ew
            where ew.event_id = p_event_id
        ) affected_user
        order by affected_user.user_id
    loop
        perform pg_advisory_xact_lock(hashtext(p_event_id::text), hashtext(v_user_id::text));
    end loop;

    -- Lock active enrollment rows in stable identifier and FIFO order
    perform 1
    from admission_offer ao
    where ao.event_id = p_event_id
    and ao.status in ('checkout_pending', 'pending')
    order by ao.admission_offer_id
    for update of ao;

    perform 1
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.status in (
        'completed',
        'pending',
        'refund-pending',
        'refund-recovery-pending',
        'refund-requested'
    )
    order by ep.event_purchase_id
    for update of ep;

    perform 1
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.status in (
        'confirmed',
        'invitation-pending',
        'registration-questions-pending'
    )
    order by ea.user_id
    for update of ea;

    perform 1
    from event_invitation_request eir
    where eir.event_id = p_event_id
    and eir.status = 'pending'
    order by eir.user_id
    for update of eir;

    perform 1
    from event_waitlist ew
    where ew.event_id = p_event_id
    order by ew.created_at, ew.user_id
    for update of ew;

    -- Expire pending checkouts and release their discount and attendee holds
    for v_event_purchase in
        update event_purchase
        set
            hold_expires_at = least(hold_expires_at, current_timestamp),
            status = 'expired',
            updated_at = current_timestamp
        where event_id = p_event_id
        and status = 'pending'
        returning
            charge_model,
            event_discount_code_id,
            event_purchase_id,
            user_id
    loop
        -- Release any reserved discount redemption after expiring the hold
        if v_event_purchase.event_discount_code_id is not null then
            perform release_event_discount_code_availability(
                v_event_purchase.event_discount_code_id
            );
        end if;

        perform release_event_checkout_attendee_hold(
            p_event_id,
            v_event_purchase.user_id
        );

        -- Tell external payers not to send money after the event is canceled
        if v_event_purchase.charge_model = 'external' then
            perform enqueue_notification(
                'event-external-payment-expired',
                jsonb_strip_nulls(jsonb_build_object(
                    'dashboard_url', '/dashboard/user?tab=events',
                    'do_not_pay', true,
                    'event_id', p_event_id,
                    'event_name', v_event_name,
                    'event_purchase_id', v_event_purchase.event_purchase_id,
                    'group_name', v_group_name,
                    'theme', v_theme
                )),
                '[]'::jsonb,
                array[v_event_purchase.user_id]
            );
        end if;
    end loop;

    -- Return abandoned checkouts to pending before canceling every active offer
    update admission_offer
    set
        status = 'pending',
        updated_at = current_timestamp
    where event_id = p_event_id
    and status = 'checkout_pending';

    for v_admission_offer in
        select
            ao.admission_offer_id,
            coalesce(ao.ticket_title, ett.title) as ticket_title,
            ao.user_id
        from admission_offer ao
        left join event_ticket_type ett
            on ett.event_ticket_type_id = ao.event_ticket_type_id
        where ao.event_id = p_event_id
        and ao.status = 'pending'
        order by ao.admission_offer_id
    loop
        update admission_offer
        set
            status = 'canceled',
            updated_at = current_timestamp
        where admission_offer_id = v_admission_offer.admission_offer_id
        and status = 'pending';

        if not found then
            continue;
        end if;

        v_canceled_user_ids := array_append(
            v_canceled_user_ids,
            v_admission_offer.user_id
        );

        perform insert_audit_log(
            'admission_offer_canceled',
            p_actor_user_id,
            'admission_offer',
            v_admission_offer.admission_offer_id,
            v_community_id,
            v_group_id,
            p_event_id,
            jsonb_build_object(
                'admission_offer_id', v_admission_offer.admission_offer_id,
                'user_id', v_admission_offer.user_id
            )
        );

        perform enqueue_notification(
            'event-admission-offer-canceled',
            jsonb_strip_nulls(jsonb_build_object(
                'admission_offer_id', v_admission_offer.admission_offer_id,
                'dashboard_url', '/dashboard/user?tab=events',
                'event_id', p_event_id,
                'event_name', v_event_name,
                'group_name', v_group_name,
                'theme', v_theme,
                'ticket_title', v_admission_offer.ticket_title
            )),
            '[]'::jsonb,
            array[v_admission_offer.user_id]
        );
    end loop;

    -- Clear pending requests and FIFO queues after reservations are released
    delete from event_invitation_request
    where event_id = p_event_id
    and status = 'pending';

    delete from event_waitlist
    where event_id = p_event_id;

    -- Return the users whose active offers were canceled
    return coalesce(v_canceled_user_ids, array[]::uuid[]);
end;
$$ language plpgsql;

-- Cancels active enrollment reservations and clears queues for an event.
create or replace function close_event_enrollment(
    p_actor_user_id uuid,
    p_event_id uuid
)
returns uuid[] as $$
declare
    v_admission_offer record;
    v_canceled_user_ids uuid[] := array[]::uuid[];
    v_event event;
    v_group "group";
    v_purchase event_purchase;
    v_theme jsonb;
    v_user_id uuid;
begin
    -- Lock the event before every tier and enrollment row closed below
    select e.*
    into v_event
    from event e
    where e.event_id = p_event_id
    for update of e;

    -- Reject missing events
    if not found then
        raise exception 'event not found';
    end if;

    -- Load the owning group shown in cancellation notifications
    select g.*
    into v_group
    from "group" g
    where g.group_id = v_event.group_id;

    -- Load shared presentation data for transactional cancellation notifications
    v_theme := site_theme();

    -- Lock ticket tiers before event-user and enrollment row locks
    perform lock_event_ticket_types(p_event_id);

    -- Acquire every affected event-user lock in stable order
    for v_user_id in
        select affected_user.user_id
        from (
            select ao.user_id
            from admission_offer ao
            where ao.event_id = p_event_id
            and admission_offer_is_active(ao.status)

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
            and (
                event_purchase_holds_seat(ep.status)
                or ep.status = 'pending'
            )

            union

            select ew.user_id
            from event_waitlist ew
            where ew.event_id = p_event_id
        ) affected_user
        order by affected_user.user_id
    loop
        -- Serialize the enrollment of each affected user
        perform lock_event_user(p_event_id, v_user_id);
    end loop;

    -- Lock active enrollment rows in stable identifier and FIFO order
    perform 1
    from admission_offer ao
    where ao.event_id = p_event_id
    and admission_offer_is_active(ao.status)
    order by ao.admission_offer_id
    for update of ao;

    perform 1
    from event_purchase ep
    where ep.event_id = p_event_id
    and (
        event_purchase_holds_seat(ep.status)
        or ep.status = 'pending'
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
    for v_purchase in
        select ep.*
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.status = 'pending'
        order by ep.event_purchase_id
    loop
        -- Expire the hold, skipping holds that are no longer pending
        if not expire_event_checkout_hold(v_purchase.event_purchase_id) then
            continue;
        end if;

        -- Tell external payers not to send money after the event is canceled
        if v_purchase.charge_model = 'external' then
            perform enqueue_notification(
                'event-external-payment-expired',
                external_payment_notification_payload(v_event, v_group, v_purchase, v_theme)
                    || jsonb_build_object('do_not_pay', true),
                '[]'::jsonb,
                array[v_purchase.user_id]
            );
        end if;
    end loop;

    -- Cancel each active offer in stable identifier order
    for v_admission_offer in
        select
            ao.admission_offer_id,
            ao.event_ticket_type_id,
            ao.source,
            coalesce(ao.ticket_title, ett.title) as ticket_title,
            ao.user_id
        from admission_offer ao
        left join event_ticket_type ett
            on ett.event_ticket_type_id = ao.event_ticket_type_id
        where ao.event_id = p_event_id
        and admission_offer_is_active(ao.status)
        order by ao.admission_offer_id
    loop
        -- Cancel the offer only while it is still active
        update admission_offer
        set
            status = 'canceled',
            updated_at = current_timestamp
        where admission_offer_id = v_admission_offer.admission_offer_id
        and admission_offer_is_active(status);

        -- Skip offers that are no longer active
        if not found then
            continue;
        end if;

        -- Track the recipient returned to the caller
        v_canceled_user_ids := array_append(
            v_canceled_user_ids,
            v_admission_offer.user_id
        );

        -- Track each canceled offer like an organizer cancellation
        perform insert_audit_log(
            case
                -- Record organizer invitations as canceled invitations
                when v_admission_offer.source = 'organizer_invitation'
                    then 'event_attendee_invitation_canceled'
                -- Record every other offer as a canceled admission offer
                else 'event_admission_offer_canceled'
            end,
            p_actor_user_id,
            'user',
            v_admission_offer.user_id,
            p_group_id => v_event.group_id,
            p_event_id => p_event_id,
            p_details => jsonb_build_object(
                'admission_offer_id', v_admission_offer.admission_offer_id,
                'event_id', p_event_id,
                'event_ticket_type_id', v_admission_offer.event_ticket_type_id,
                'user_id', v_admission_offer.user_id
            )
        );

        -- Notify the recipient that the offer was canceled
        perform enqueue_notification(
            'event-admission-offer-canceled',
            jsonb_strip_nulls(jsonb_build_object(
                'admission_offer_id', v_admission_offer.admission_offer_id,
                'dashboard_url', '/dashboard/user?tab=events',
                'event_id', p_event_id,
                'event_name', v_event.name,
                'group_name', v_group.name,
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

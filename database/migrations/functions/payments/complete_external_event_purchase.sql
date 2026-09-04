-- Completes a pending external purchase after an organizer marks it paid.
create or replace function complete_external_event_purchase(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_purchase_id uuid,
    p_details text,
    p_notification_attachments jsonb default '[]'::jsonb,
    p_notification_template_data jsonb default null
)
returns jsonb as $$
declare
    v_admission_offer admission_offer;
    v_event event;
    v_group "group";
    v_purchase event_purchase;
begin
    -- Resolve immutable parent identifiers before taking locks
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id;

    -- Reject purchases that do not exist
    if not found then
        raise exception 'purchase not found' using errcode = 'OCG01';
    end if;

    -- Reject purchases that belong to another group
    if not exists (
        select 1
        from event e
        where e.event_id = v_purchase.event_id
        and e.group_id = p_group_id
    ) then
        raise exception 'purchase not found' using errcode = 'OCG01';
    end if;

    -- Reject holds that already expired before locks are taken
    if v_purchase.status in ('expired', 'pending')
       and v_purchase.hold_expires_at is not null
       and v_purchase.hold_expires_at <= current_timestamp then
        raise exception 'purchase hold has expired' using errcode = 'OCG01';
    end if;

    -- Lock the group before the event to match dashboard event mutations
    select g.*
    into v_group
    from "group" g
    where g.group_id = p_group_id
    for update of g;

    -- Reject missing groups after the lock attempt
    if not found then
        raise exception 'purchase not found' using errcode = 'OCG01';
    end if;

    -- Lock the event before the purchase to match checkout and attendance flows
    select e.*
    into v_event
    from event e
    where e.event_id = v_purchase.event_id
    and e.group_id = p_group_id
    for update of e;

    -- Reject events that left the requested group
    if not found then
        raise exception 'purchase not found' using errcode = 'OCG01';
    end if;

    -- Reconcile under the global event, tier, user, and purchase lock order
    perform reconcile_event_enrollment(v_event.event_id, v_purchase.event_ticket_type_id);

    -- Lock the purchase before validating and completing it
    select ep.*
    into v_purchase
    from event_purchase ep
    where ep.event_purchase_id = p_event_purchase_id
    for update of ep;

    -- Reject purchases removed while waiting for the lock
    if not found then
        raise exception 'purchase not found' using errcode = 'OCG01';
    end if;

    -- Load the reservation the purchase claims
    if v_purchase.admission_offer_id is not null then
        select ao.*
        into v_admission_offer
        from admission_offer ao
        where ao.admission_offer_id = v_purchase.admission_offer_id;
    end if;

    -- Return early on idempotent replays of a completed external purchase
    if v_purchase.status = 'completed' and v_purchase.charge_model = 'external' then
        return jsonb_build_object(
            'community_id', v_group.community_id,
            'event_id', v_event.event_id,
            'transitioned', false,
            'user_id', v_purchase.user_id
        );
    end if;

    -- Reject purchases that are not an external pending hold
    if v_purchase.charge_model <> 'external' then
        raise exception 'only external purchases can be marked paid locally' using errcode = 'OCG01';
    end if;

    -- Reject purchases that left the pending state
    if v_purchase.status <> 'pending' then
        raise exception 'purchase is no longer pending' using errcode = 'OCG01';
    end if;

    -- Reject holds that expired during reconciliation
    if v_purchase.hold_expires_at is not null and v_purchase.hold_expires_at <= current_timestamp then
        raise exception 'purchase hold has expired' using errcode = 'OCG01';
    end if;

    -- Reject completion while another purchase is in refund recovery
    if event_has_pending_refund_recovery(v_purchase.event_id, v_purchase.user_id, v_purchase.event_purchase_id) then
        raise exception 'checkout is unavailable while refund recovery is in progress' using errcode = 'OCG01';
    end if;

    -- Ensure the event is still active before completing the purchase
    if not event_accepts_enrollment(v_event, v_group) then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Complete the linked reservation before creating active attendance
    if v_purchase.admission_offer_id is not null
       and not complete_event_purchase_admission_offer(v_purchase.admission_offer_id) then
        raise exception 'admission offer is no longer available' using errcode = 'OCG01';
    end if;

    -- Never complete the purchase without a confirmed attendee row
    if not confirm_event_purchase_attendee(
        v_purchase.event_id,
        v_purchase.user_id,
        coalesce(v_admission_offer.source = 'organizer_invitation', false)
    ) then
        raise exception 'attendee cannot be confirmed for this event' using errcode = 'OCG01';
    end if;

    -- Persist the completed external purchase and organizer payment details
    update event_purchase
    set
        completed_at = current_timestamp,
        external_payment_details = nullif(btrim(p_details), ''),
        external_payment_marked_by_user_id = p_actor_user_id,
        hold_expires_at = null,
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Record the organizer action after the state transition succeeds
    perform insert_audit_log(
        'event_purchase_external_payment_completed',
        p_actor_user_id,
        'event',
        v_event.event_id,
        v_group.community_id,
        p_group_id,
        v_event.event_id,
        jsonb_build_object(
            'event_purchase_id', p_event_purchase_id,
            'user_id', v_purchase.user_id
        )
    );

    -- Enqueue the welcome notification in the same transaction as completion
    if p_notification_template_data is not null then
        perform enqueue_notification(
            'event-welcome',
            p_notification_template_data,
            coalesce(p_notification_attachments, '[]'::jsonb),
            array[v_purchase.user_id]
        );
    end if;

    -- Return the identifiers needed by the caller after completion
    return jsonb_build_object(
        'community_id', v_group.community_id,
        'event_id', v_event.event_id,
        'transitioned', true,
        'user_id', v_purchase.user_id
    );
end;
$$ language plpgsql;

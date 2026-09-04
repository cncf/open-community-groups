-- Completes a pending free-ticket purchase and returns its notification data.
create or replace function complete_free_event_purchase(
    p_event_purchase_id uuid
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
    join event e on e.group_id = g.group_id
    where e.event_id = v_purchase.event_id
    for update of g;

    -- Reject purchases whose event or group disappeared
    if not found then
        raise exception 'purchase not found' using errcode = 'OCG01';
    end if;

    -- Lock the event before the purchase to match checkout and attendance flows
    select e.*
    into v_event
    from event e
    where e.event_id = v_purchase.event_id
    and e.group_id = v_group.group_id
    for update of e;

    -- Reject events that left the group
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

    -- Reject purchases that left the pending state
    if v_purchase.status <> 'pending' then
        raise exception 'purchase is no longer pending' using errcode = 'OCG01';
    end if;

    -- Reject paid purchases, which only the provider webhook completes
    if v_purchase.amount_minor <> 0 then
        raise exception 'only free purchases can be completed locally' using errcode = 'OCG01';
    end if;

    -- Reject holds that expired during reconciliation
    if v_purchase.hold_expires_at is not null and v_purchase.hold_expires_at <= current_timestamp then
        raise exception 'purchase hold has expired' using errcode = 'OCG01';
    end if;

    -- Reject completion while another purchase is in refund recovery
    if event_has_pending_refund_recovery(v_purchase.event_id, v_purchase.user_id, v_purchase.event_purchase_id) then
        raise exception 'checkout is unavailable while refund recovery is in progress' using errcode = 'OCG01';
    end if;

    -- Ensure the event is still active before completing the free purchase
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

    -- Persist the completed free purchase
    update event_purchase
    set
        completed_at = current_timestamp,
        hold_expires_at = null,
        status = 'completed',
        updated_at = current_timestamp
    where event_purchase_id = p_event_purchase_id;

    -- Return the identifiers needed by the caller after completion
    return jsonb_build_object(
        'community_id', v_group.community_id,
        'event_id', v_event.event_id,
        'user_id', v_purchase.user_id
    );
end;
$$ language plpgsql;

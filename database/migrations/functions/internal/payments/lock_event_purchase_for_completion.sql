-- Locks a purchase being completed locally with its group and event in the
-- global order, reconciling the event enrollment before the purchase lock. A
-- null group derives it from the purchase event.
create or replace function lock_event_purchase_for_completion(
    p_event_purchase_id uuid,
    p_group_id uuid
)
returns table (
    admission_offer_row admission_offer,
    event_row event,
    group_row "group",
    purchase_row event_purchase
) as $$
declare
    v_admission_offer admission_offer;
    v_event event;
    v_group "group";
    v_group_id uuid;
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

    -- Resolve the group that owns the purchase event
    select e.group_id
    into v_group_id
    from event e
    where e.event_id = v_purchase.event_id
    and (p_group_id is null or e.group_id = p_group_id);

    -- Reject purchases that belong to another group
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
    where g.group_id = v_group_id
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
    and e.group_id = v_group.group_id
    for update of e;

    -- Reject events that left the group
    if not found then
        raise exception 'purchase not found' using errcode = 'OCG01';
    end if;

    -- Reconcile under the global event, tier, user, and purchase lock order
    perform reconcile_event_enrollment(v_event.event_id, v_purchase.event_ticket_type_id);

    -- Lock the purchase before the caller validates and completes it
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

    -- Return the locked rows for the caller's completion decisions
    return query select v_admission_offer, v_event, v_group, v_purchase;
end;
$$ language plpgsql;

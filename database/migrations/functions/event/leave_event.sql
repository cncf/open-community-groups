-- Leave an event as an attendee.
create or replace function leave_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_configured_provider text default null
) returns json as $$
declare
    v_event event;
    v_purchase_amount_minor bigint;
    v_purchase_id uuid;
    v_purchase_ticket_type_id uuid;
begin
    -- Lock and validate the attendee-visible event
    v_event := lock_active_event(p_community_id, null, p_event_id, true);

    -- Lock ticket tiers before serializing this attendee's enrollment state
    perform 1
    from event_ticket_type ett
    where ett.event_id = v_event.event_id
    order by ett.event_ticket_type_id
    for update of ett;

    -- Serialize this attendee's enrollment transitions
    perform pg_advisory_xact_lock(hashtext(v_event.event_id::text), hashtext(p_user_id::text));

    -- Paid attendees must request a refund instead of leaving the event
    select
        ep.amount_minor,
        ep.event_purchase_id,
        ep.event_ticket_type_id
    into
        v_purchase_amount_minor,
        v_purchase_id,
        v_purchase_ticket_type_id
    from event_purchase ep
    where ep.event_id = p_event_id
    and ep.user_id = p_user_id
    and ep.status in ('completed', 'refund-requested')
    order by ep.created_at desc, ep.event_purchase_id desc
    limit 1
    for update of ep;

    -- Reject paid attendance that requires a refund request
    if v_purchase_amount_minor > 0 then
        raise exception 'paid attendees must request a refund instead of leaving the event' using errcode = 'OCG01';
    end if;

    -- Preserve the confirmed attendee row while removing active attendance
    update event_attendee
    set
        attendance_canceled_at = current_timestamp,
        attendance_canceled_by_user_id = p_user_id,
        checked_in = false,
        checked_in_at = null,
        status = 'attendance-canceled'
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'confirmed';

    -- Return after canceling active attendance
    if found then
        -- If the user had a free ticket purchase, delegate the refund transition
        if v_purchase_id is not null then
            perform refund_free_event_purchase(v_purchase_id);
        end if;

        -- Reconcile the released ticket-tier capacity
        perform reconcile_event_enrollment(
            p_event_id,
            v_purchase_ticket_type_id,
            p_configured_provider
        );

        return json_build_object('left_status', 'attendee');
    end if;

    -- Otherwise remove the user from the waiting list
    delete from event_waitlist
    where event_id = p_event_id
    and user_id = p_user_id;

    -- Return after removing a waitlist position
    if found then
        return json_build_object('left_status', 'waitlisted');
    end if;

    -- Otherwise remove a pending invitation request
    delete from event_invitation_request
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'pending';

    -- Return after canceling a pending approval request
    if found then
        return json_build_object('left_status', 'pending-approval');
    end if;

    -- Reject users without active enrollment
    raise exception 'user is not attending or waitlisted for this event' using errcode = 'OCG01';
end;
$$ language plpgsql;

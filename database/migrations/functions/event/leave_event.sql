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
    v_event := lock_active_event(p_community_id, null, p_event_id);

    -- Lock ticket tiers before serializing this attendee's enrollment state
    perform lock_event_ticket_types(v_event.event_id);

    -- Serialize this attendee's enrollment transitions
    perform lock_event_user(v_event.event_id, p_user_id);

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

    -- Return after canceling confirmed attendance, preserving the attendee row
    if mark_event_attendance_canceled(p_event_id, p_user_id, p_user_id) then
        -- Refund the free ticket purchase locally when the user had one
        if v_purchase_id is not null then
            perform refund_event_purchase_locally(v_purchase_id, p_user_id);
        end if;

        -- Reconcile the released ticket-tier capacity
        perform reconcile_event_enrollment(
            p_event_id,
            v_purchase_ticket_type_id,
            p_configured_provider
        );

        -- Report the canceled attendance
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

-- Validates that an attendee can begin checkout for an event.
create or replace function prepare_event_checkout_validate_attendee_state(
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_enrollment record;
begin
    -- Load the user's enrollment facts before deciding whether to proceed
    select *
    into v_enrollment
    from event_user_enrollment(p_event_id, p_user_id);

    if v_enrollment.attendee_status = 'confirmed' then
        raise exception 'user is already attending this event' using errcode = 'OCG01';
    end if;

    if v_enrollment.attendee_status in ('invitation-pending', 'invitation-rejected') then
        raise exception 'user has a pending or rejected invitation for this event' using errcode = 'OCG01';
    end if;

    -- Reject queued users before they can bypass waitlist promotion
    if v_enrollment.waitlisted then
        raise exception 'user is already on the waiting list for this event' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;

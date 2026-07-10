-- Validates that an attendee can begin checkout for an event.
create or replace function prepare_event_checkout_validate_attendee_state(
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_attendee_status text;
begin
    -- Load the attendee lifecycle state before deciding whether to proceed
    select status
    into v_attendee_status
    from event_attendee
    where event_id = p_event_id
    and user_id = p_user_id;

    if v_attendee_status = 'confirmed' then
        raise exception 'user is already attending this ticketed event';
    end if;

    if v_attendee_status in ('invitation-pending', 'invitation-rejected') then
        raise exception 'user has a pending or rejected invitation for this event';
    end if;
end;
$$ language plpgsql;

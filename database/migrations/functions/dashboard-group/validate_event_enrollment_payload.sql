-- validate_event_enrollment_payload validates shared event enrollment settings.
create or replace function validate_event_enrollment_payload(
    p_attendee_approval_required boolean,
    p_ticket_types jsonb,
    p_waitlist_enabled boolean
)
returns void as $$
begin
    -- Return stable dashboard errors before lower-level constraints or writes run
    if p_attendee_approval_required = true and p_waitlist_enabled = true then
        raise exception 'approval-required events cannot enable waitlist';
    end if;

    if p_attendee_approval_required = true and p_ticket_types is not null then
        raise exception 'approval-required events cannot be ticketed';
    end if;
end;
$$ language plpgsql;

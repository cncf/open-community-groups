-- Checks in a confirmed event attendee, auditing only the first transition.
-- The caller must have locked and validated the event.
create or replace function check_in_event_attendee(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns table (checked_in_at timestamptz, transitioned boolean) as $$
declare
    v_checked_in boolean;
    v_checked_in_at timestamptz;
begin
    -- Lock the confirmed attendee and capture the current state
    select ea.checked_in, ea.checked_in_at
    into v_checked_in, v_checked_in_at
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    and ea.status = 'confirmed'
    for update of ea;

    -- Reject users without confirmed attendance
    if not found then
        raise exception 'attendance is not confirmed' using errcode = 'OCG01';
    end if;

    -- Preserve the original timestamp and audit record on repeated check-ins
    if v_checked_in then
        return query select v_checked_in_at, false;
        return;
    end if;

    -- Persist the first check-in transition
    update event_attendee ea
    set
        checked_in = true,
        checked_in_at = current_timestamp
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    returning ea.checked_in_at into v_checked_in_at;

    -- Record the organizer action after the state transition succeeds
    perform insert_audit_log(
        'event_attendee_checked_in',
        p_actor_user_id,
        'user',
        p_user_id,
        p_community_id,
        p_group_id,
        p_event_id
    );

    -- Report that this call performed the transition
    return query select v_checked_in_at, true;
end;
$$ language plpgsql;

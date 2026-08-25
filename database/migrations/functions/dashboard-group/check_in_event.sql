-- Checks in a confirmed event attendee and records the first transition.
create or replace function check_in_event(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns boolean as $$
declare
    v_checked_in boolean;
    v_group_id uuid;
begin
    -- Lock and validate the selected event scope
    select e.group_id
    into v_group_id
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    and g.active = true
    and g.deleted = false
    and e.canceled = false
    and e.deleted = false
    and e.published = true
    for update of e;

    -- Reject unavailable events before attendee mutation
    if not found then
        raise exception 'event unavailable for check-in';
    end if;

    -- Lock the confirmed attendee and capture the current state
    select ea.checked_in
    into v_checked_in
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    and ea.status = 'confirmed'
    for update;

    -- Reject users without confirmed attendance
    if not found then
        raise exception 'attendance is not confirmed';
    end if;

    -- Preserve the original timestamp and audit record on repeated check-ins
    if v_checked_in then
        return false;
    end if;

    -- Persist the first check-in transition
    update event_attendee
    set
        checked_in = true,
        checked_in_at = current_timestamp
    where event_id = p_event_id
    and user_id = p_user_id;

    -- Record the organizer action after the state transition succeeds
    perform insert_audit_log(
        'event_attendee_checked_in',
        p_actor_user_id,
        'user',
        p_user_id,
        p_community_id,
        v_group_id,
        p_event_id
    );

    -- Report that this call performed the transition
    return true;
end;
$$ language plpgsql;

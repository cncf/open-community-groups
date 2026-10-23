-- Checks in a confirmed attendee of an event in the selected group and records
-- the first transition. Manual check-in is not limited to the scanner window.
create or replace function check_in_event(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_group_id uuid,
    p_user_id uuid
)
returns boolean as $$
declare
    v_event_id uuid;
    v_transitioned boolean;
begin
    -- Lock the event and validate it is available in the selected group
    select e.event_id
    into v_event_id
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and g.community_id = p_community_id
    and is_event_public(e, g)
    and e.canceled = false
    for update of e;

    -- Reject unavailable events before attendee mutation
    if not found then
        raise exception 'event unavailable for check-in' using errcode = 'OCG01';
    end if;

    -- Apply the shared atomic transition and audit behavior
    select ci.transitioned
    into v_transitioned
    from check_in_event_attendee(
        p_actor_user_id,
        p_community_id,
        p_group_id,
        p_event_id,
        p_user_id
    ) ci;

    -- Report whether this call performed the transition
    return v_transitioned;
end;
$$ language plpgsql;

-- Manually checks in an event attendee and records the action.
create or replace function manual_check_in_event(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_group_id uuid;
begin
    -- Resolve the group so the audit row carries full scope
    select e.group_id
    into v_group_id
    from event e
    where e.event_id = p_event_id;

    -- Perform the check-in using the shared event logic
    perform check_in_event(p_community_id, p_event_id, p_user_id, true);

    -- Track the manual check-in
    perform insert_audit_log(
        'event_attendee_checked_in',
        p_actor_user_id,
        'user',
        p_user_id,
        p_community_id,
        v_group_id,
        p_event_id
    );
end;
$$ language plpgsql;

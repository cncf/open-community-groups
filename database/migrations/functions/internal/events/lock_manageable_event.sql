-- Locks a group's event that organizers can still manage (not deleted and,
-- unless p_allow_canceled, not canceled) and returns its row. Callers that
-- lock the group lock it first.
create or replace function lock_manageable_event(
    p_group_id uuid,
    p_event_id uuid,
    p_allow_canceled boolean
)
returns event as $$
declare
    v_event event;
begin
    -- Lock the group's event when organizers can still manage it
    select e.*
    into v_event
    from event e
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and (p_allow_canceled or e.canceled = false)
    for update of e;

    -- Reject missing, foreign, deleted or disallowed canceled events
    if not found then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Return the locked event row
    return v_event;
end;
$$ language plpgsql;

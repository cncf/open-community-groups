-- Locks an event whose surveys organizers can manage and returns its row. The
-- event must belong to the group, its group must be active (a deleted group is
-- never active), and the event must be neither deleted nor canceled. Ended
-- events are allowed because surveys are managed after the event. Callers lock
-- the event before any of its surveys.
create or replace function lock_event_for_surveys(
    p_group_id uuid,
    p_event_id uuid
)
returns event as $$
declare
    v_event event;
begin
    -- Lock the event when it is still manageable within the group
    select e.*
    into v_event
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and g.active = true
    and e.canceled = false
    and e.deleted = false
    for update of e;

    -- Reject missing, foreign, canceled or deleted events and inactive groups
    if not found then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Return the locked event row
    return v_event;
end;
$$ language plpgsql;

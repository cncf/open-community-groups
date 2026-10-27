-- Locks an event that accepts enrollment transitions, as defined by
-- event_accepts_enrollment, and returns its row. The event must belong to the
-- given community or group.
create or replace function lock_active_event(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns event as $$
declare
    v_event event;
begin
    -- Require a scope so the lock never spans communities
    if p_community_id is null and p_group_id is null then
        raise exception 'lock_active_event requires a community or group scope';
    end if;

    -- Lock the scoped event when it still accepts enrollment transitions
    select e.*
    into v_event
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and (p_community_id is null or g.community_id = p_community_id)
    and (p_group_id is null or e.group_id = p_group_id)
    and event_accepts_enrollment(e, g)
    for update of e;

    -- Reject events outside the scope or no longer accepting enrollment
    if not found then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    -- Return the locked event row
    return v_event;
end;
$$ language plpgsql;

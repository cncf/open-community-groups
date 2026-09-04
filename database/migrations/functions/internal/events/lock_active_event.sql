-- Locks an event that is still open to attendee and organizer actions and
-- returns its row. The event must belong to the given community or group,
-- its group must be active, and the event must not be deleted, canceled or
-- already over. Callers that only act on published events pass
-- p_require_published.
create or replace function lock_active_event(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_require_published boolean
)
returns event as $$
declare
    v_event event;
begin
    -- Require a scope so the lock never spans communities
    if p_community_id is null and p_group_id is null then
        raise exception 'lock_active_event requires a community or group scope';
    end if;

    select e.*
    into v_event
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and (p_community_id is null or g.community_id = p_community_id)
    and (p_group_id is null or e.group_id = p_group_id)
    and g.active = true
    and e.deleted = false
    and e.canceled = false
    and (not p_require_published or e.published = true)
    and (
        event_effective_ends_at(e) is null
        or event_effective_ends_at(e) >= current_timestamp
    )
    for update of e;

    if not found then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;

    return v_event;
end;
$$ language plpgsql;

-- Validates that an event exists in the community and is active for attendees.
create or replace function ensure_event_is_active(p_community_id uuid, p_event_id uuid)
returns void as $$
begin
    -- Validate that the event is currently available to attendees
    if not exists (
        select 1
        from event e
        join "group" g on g.group_id = e.group_id
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and g.active = true
        and e.deleted = false
        and e.published = true
        and e.canceled = false
        and (
            event_effective_ends_at(e) is null
            or event_effective_ends_at(e) >= current_timestamp
        )
    ) then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;

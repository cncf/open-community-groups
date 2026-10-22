-- Validates that an event exists in the community and is active for attendees.
create or replace function ensure_event_is_active(p_community_id uuid, p_event_id uuid)
returns void as $$
begin
    -- Validate that the community event still accepts enrollment transitions
    if not exists (
        select 1
        from event e
        join "group" g on g.group_id = e.group_id
        where e.event_id = p_event_id
        and g.community_id = p_community_id
        and event_accepts_enrollment(e, g)
    ) then
        raise exception 'event not found or inactive' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;

-- Attend an event as an attendee.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns void as $$
begin
    -- Check if event exists in the community, is active and can be attended
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
            coalesce(e.ends_at, e.starts_at) is null
            or coalesce(e.ends_at, e.starts_at) >= current_timestamp
        )
    ) then
        raise exception 'event not found or inactive';
    end if;

    -- Add user as event attendee
    begin
        insert into event_attendee (event_id, user_id)
        values (p_event_id, p_user_id);
    exception
        when unique_violation then
            raise exception 'user is already attending this event';
    end;
end;
$$ language plpgsql;

-- Attend an event as an attendee.
create or replace function attend_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
) returns void as $$
declare
    v_capacity int;
    v_attendee_count int;
begin
    -- Check if event exists in the community, is active and can be attended
    select e.capacity
    into v_capacity
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
    for update of e;
    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Check if event has capacity for more attendees
    if v_capacity is not null then
        select count(*) into v_attendee_count
        from event_attendee
        where event_id = p_event_id;

        if v_attendee_count >= v_capacity then
            raise exception 'event has reached capacity';
        end if;
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

-- Check-in a user for an event.
create or replace function check_in_event(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_bypass_window boolean
)
returns void as $$
declare
    v_starts_at timestamptz;
begin
    -- Get event dates, checking its validity and active status
    select e.starts_at
    into v_starts_at
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    and g.active = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false
    for update of e;
    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Validate start time and check-in window unless bypassing
    if not p_bypass_window then
        if v_starts_at is null then
            raise exception 'event has no start time';
        end if;
        if not is_event_check_in_window_open(p_community_id, p_event_id) then
            raise exception 'check-in window closed';
        end if;
    end if;

    -- Check if user is registered for the event after validating it exists
    if not exists (
        select 1
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.user_id = p_user_id
    ) then
        raise exception 'user is not registered for this event';
    end if;

    -- Update check-in status
    update event_attendee
    set
        checked_in = true,
        checked_in_at = coalesce(checked_in_at, now())
    where event_id = p_event_id
    and user_id = p_user_id;
    if not found then
        raise exception 'failed to update check-in status';
    end if;
end;
$$ language plpgsql;

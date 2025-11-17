-- Check if check-in window is open for an event.
create or replace function is_event_check_in_window_open(
    p_community_id uuid,
    p_event_id uuid
) returns boolean as $$
declare
    v_check_in_start timestamptz;
    v_check_in_end timestamptz;
    v_check_in_window_start_offset interval := interval '2 hours';
    v_ends_at timestamptz;
    v_now timestamptz := now();
    v_starts_at timestamptz;
    v_timezone text;
begin
    -- Get event dates and timezone
    select e.starts_at, e.ends_at, e.timezone
    into v_starts_at, v_ends_at, v_timezone
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    and g.active = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false;
    if not found or v_starts_at is null then
        return false;
    end if;

    -- Calculate check-in window
    -- (check-in opens 2 hours before event start to allow early arrivals)
    v_check_in_start := v_starts_at - v_check_in_window_start_offset;
    if v_ends_at is not null and date_trunc('day', v_starts_at at time zone v_timezone) != date_trunc('day', v_ends_at at time zone v_timezone) then
        -- Multi-day event: allow until end of last day
        v_check_in_end := (date_trunc('day', v_ends_at at time zone v_timezone) + interval '1 day') at time zone v_timezone;
    else
        -- Single day or same-day event: allow until end of start day
        v_check_in_end := (date_trunc('day', v_starts_at at time zone v_timezone) + interval '1 day') at time zone v_timezone;
    end if;

    -- Check if within check-in window
    return v_now >= v_check_in_start and v_now < v_check_in_end;
end;
$$ language plpgsql;

-- Validates that session timestamps fall within the bounds of their event.
create or replace function check_session_within_event_bounds()
returns trigger as $$
declare
    v_event_ends_at timestamptz;
    v_event_starts_at timestamptz;
begin
    -- Allow legacy data imports to bypass this validation
    if coalesce(current_setting('ocg.skip_session_bounds_check', true)::boolean, false) then
        return new;
    end if;

    -- Load the event bounds
    select starts_at, ends_at into v_event_starts_at, v_event_ends_at
    from event
    where event_id = new.event_id;

    -- Validate only when the event has both bounds set
    if v_event_starts_at is not null and v_event_ends_at is not null then
        -- Reject sessions starting outside the event
        if new.starts_at < v_event_starts_at or new.starts_at > v_event_ends_at then
            raise exception 'session starts_at must be within event bounds' using errcode = 'OCG01';
        end if;

        -- Reject sessions ending after the event
        if new.ends_at is not null and new.ends_at > v_event_ends_at then
            raise exception 'session ends_at must be within event bounds' using errcode = 'OCG01';
        end if;
    end if;

    -- Return the validated session row
    return new;
end;
$$ language plpgsql;

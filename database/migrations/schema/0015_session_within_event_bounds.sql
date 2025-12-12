-- Add trigger to enforce session timestamps are within event bounds.
-- When an event has both starts_at and ends_at set, all sessions must have
-- their timestamps within [event.starts_at, event.ends_at].

-- Trigger function to validate session timestamps within event bounds
create or replace function check_session_within_event_bounds()
returns trigger as $$
declare
    v_event_ends_at timestamptz;
    v_event_starts_at timestamptz;
begin
    -- Get event bounds
    select starts_at, ends_at into v_event_starts_at, v_event_ends_at
    from event
    where event_id = NEW.event_id;

    -- Only validate if event has both bounds set
    if v_event_starts_at is not null and v_event_ends_at is not null then
        -- Session starts_at must be within event bounds
        if NEW.starts_at < v_event_starts_at or NEW.starts_at > v_event_ends_at then
            raise exception 'session starts_at must be within event bounds';
        end if;

        -- Session ends_at (if set) must be within event bounds
        if NEW.ends_at is not null and NEW.ends_at > v_event_ends_at then
            raise exception 'session ends_at must be within event bounds';
        end if;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on session INSERT/UPDATE
create trigger session_within_event_bounds_check
    before insert or update on session
    for each row
    execute function check_session_within_event_bounds();

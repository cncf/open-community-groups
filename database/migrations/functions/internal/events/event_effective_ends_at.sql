-- Returns the moment an event stops being current: its end, or its start when
-- no end is configured. Null when the event has no dates.
create or replace function event_effective_ends_at(p_event event)
returns timestamptz as $$
    select coalesce(p_event.ends_at, p_event.starts_at);
$$ language sql immutable;

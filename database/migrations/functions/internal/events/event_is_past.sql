-- Reports whether an event is over: its end, or its start when no end is set,
-- is before the current transaction time. Dateless events are never past. This
-- is the same rule as the Rust Event::is_past.
create or replace function event_is_past(p_event event)
returns boolean as $$
    select coalesce(event_effective_ends_at(p_event) < current_timestamp, false);
$$ language sql stable;

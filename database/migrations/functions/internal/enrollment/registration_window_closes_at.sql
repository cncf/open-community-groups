-- Returns when an event registration window closes, or null when it never closes.
create or replace function registration_window_closes_at(
    p_registration_starts_at timestamptz,
    p_registration_ends_at timestamptz,
    p_event_starts_at timestamptz
)
returns timestamptz as $$
    select case
        when p_registration_ends_at is not null then p_registration_ends_at
        when p_registration_starts_at is not null then p_event_starts_at
    end;
$$ language sql immutable;

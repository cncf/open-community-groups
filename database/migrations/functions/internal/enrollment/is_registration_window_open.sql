-- Returns whether an event registration window is currently open.
create or replace function is_registration_window_open(
    p_registration_starts_at timestamptz,
    p_registration_ends_at timestamptz,
    p_event_starts_at timestamptz
)
returns boolean as $$
    select
        (p_registration_starts_at is null or current_timestamp >= p_registration_starts_at)
        and (window_close.closes_at is null or current_timestamp < window_close.closes_at)
    from (
        select registration_window_closes_at(
            p_registration_starts_at,
            p_registration_ends_at,
            p_event_starts_at
        ) as closes_at
    ) window_close;
$$ language sql stable;

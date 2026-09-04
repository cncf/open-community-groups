-- Returns whether an event registration window is currently open.
create or replace function is_registration_window_open(
    p_registration_starts_at timestamptz,
    p_registration_ends_at timestamptz,
    p_event_starts_at timestamptz
)
returns boolean as $$
    select (
        (p_registration_starts_at is null or current_timestamp >= p_registration_starts_at)
        and (
            (
                p_registration_ends_at is not null
                and current_timestamp < p_registration_ends_at
            )
            or (
                p_registration_ends_at is null
                and (
                    p_registration_starts_at is null
                    or p_event_starts_at is null
                    or current_timestamp < p_event_starts_at
                )
            )
        )
    );
$$ language sql stable;

-- Add optional event registration window dates.

alter table event
    add column registration_starts_at timestamptz,
    add column registration_ends_at timestamptz,
    add constraint event_registration_window_order_chk check (
        registration_starts_at is null
        or registration_ends_at is null
        or registration_starts_at < registration_ends_at
    ),
    add constraint event_registration_end_before_event_start_chk check (
        registration_ends_at is null
        or starts_at is null
        or registration_ends_at <= starts_at
    ),
    add constraint event_registration_start_before_event_start_chk check (
        registration_starts_at is null
        or starts_at is null
        or registration_starts_at <= starts_at
    );

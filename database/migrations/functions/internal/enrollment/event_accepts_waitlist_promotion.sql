-- Reports whether waitlist queue heads of an event may be promoted into
-- admission offers: the event accepts enrollment, has not started and its
-- public registration window is open.
create or replace function event_accepts_waitlist_promotion(
    p_event event,
    p_group "group"
)
returns boolean as $$
    select event_accepts_enrollment(p_event, p_group)
        and (p_event.starts_at is null or p_event.starts_at > current_timestamp)
        and is_registration_window_open(
            p_event.registration_starts_at,
            p_event.registration_ends_at,
            p_event.starts_at
        );
$$ language sql stable;

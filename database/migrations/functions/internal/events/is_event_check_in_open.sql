-- Checks whether an event accepts scanner check-ins: it is publicly visible,
-- not canceled and scheduled, and its window has not closed. The window ends
-- at the event end, or at the end of the start day in the event timezone when
-- no end is configured, unlike event_effective_ends_at.
create or replace function is_event_check_in_open(p_event event, p_group "group")
returns boolean as $$
    select is_event_public(p_event, p_group)
        and p_event.canceled = false
        and p_event.starts_at is not null
        and current_timestamp < coalesce(
            p_event.ends_at,
            (
                date_trunc('day', p_event.starts_at at time zone p_event.timezone)
                + interval '1 day'
            ) at time zone p_event.timezone
        );
$$ language sql stable;

-- Reports whether an event still accepts enrollment transitions: its group is
-- active and the event is published, not deleted, not canceled and not over.
-- This is the row-based form of the lock_active_event predicate for callers
-- that already hold the rows.
create or replace function event_accepts_enrollment(
    p_event event,
    p_group "group"
)
returns boolean as $$
    select p_group.active
        and p_event.published
        and not p_event.deleted
        and not p_event.canceled
        and (
            event_effective_ends_at(p_event) is null
            or event_effective_ends_at(p_event) >= current_timestamp
        );
$$ language sql stable;

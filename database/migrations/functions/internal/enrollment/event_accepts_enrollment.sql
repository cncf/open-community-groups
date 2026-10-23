-- Reports whether an event still accepts enrollment transitions: its group is
-- active and the event is published, not deleted, not canceled and not over.
-- Single home of the enrollment-active rule; lock_active_event,
-- ensure_event_is_active and list_user_event_invitations delegate to it.
create or replace function event_accepts_enrollment(
    p_event event,
    p_group "group"
)
returns boolean as $$
    select p_group.active
        and p_event.published
        and not p_event.deleted
        and not p_event.canceled
        and not event_is_past(p_event);
$$ language sql stable;

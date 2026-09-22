-- Returns whether a user's enrollment for an event moved past a stale offer of the given source:
-- a newer offer from another source or any enrollment that excludes a new offer.
create or replace function is_event_enrollment_superseded(
    p_event_id uuid,
    p_user_id uuid,
    p_source text,
    p_since timestamptz
)
returns boolean as $$
    select exists (
        select 1
        from admission_offer ao
        where ao.event_id = p_event_id
        and ao.created_at > p_since
        and ao.source <> p_source
        and ao.user_id = p_user_id
    )
    or event_user_enrollment_conflict(p_event_id, p_user_id, null) is not null;
$$ language sql stable;

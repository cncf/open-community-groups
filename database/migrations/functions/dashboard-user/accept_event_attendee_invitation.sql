-- Accepts a pending organizer-created event invitation.
create or replace function accept_event_attendee_invitation(
    p_actor_user_id uuid,
    p_event_id uuid,
    p_registration_answers jsonb default null,
    p_configured_provider text default null
)
returns uuid as $$
declare
    v_community_id uuid;
    v_group_id uuid;
begin
    -- Lock and validate the event, but intentionally do not enforce capacity
    select
        g.community_id,
        e.group_id
    into
        v_community_id,
        v_group_id
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and g.active = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false
    and (
        coalesce(e.ends_at, e.starts_at) is null
        or coalesce(e.ends_at, e.starts_at) >= current_timestamp
    )
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Expire stale offers and preserve RSVP queue priority before the claim
    perform reconcile_event_enrollment(p_event_id, null, p_configured_provider);

    -- Serialize the claim with attendee and offer transitions
    perform pg_advisory_xact_lock(
        hashtext(p_event_id::text),
        hashtext(p_actor_user_id::text)
    );

    -- Complete the owned organizer invitation offer
    if not complete_non_ticketed_event_admission_offer(
        v_community_id,
        p_event_id,
        p_actor_user_id,
        p_registration_answers
    ) then
        raise exception 'pending event invitation not found';
    end if;

    return v_community_id;
end;
$$ language plpgsql;

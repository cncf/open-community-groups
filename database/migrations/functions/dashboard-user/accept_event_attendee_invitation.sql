-- Accepts a pending organizer-created event invitation.
create or replace function accept_event_attendee_invitation(
    p_actor_user_id uuid,
    p_event_id uuid
)
returns uuid as $$
declare
    v_alliance_id uuid;
    v_group_id uuid;
begin
    -- Lock and validate the event, but intentionally do not enforce capacity
    select
        g.alliance_id,
        e.group_id
    into
        v_alliance_id,
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

    -- Confirm the pending invitation
    update event_attendee
    set status = 'confirmed'
    where event_id = p_event_id
    and user_id = p_actor_user_id
    and status = 'invitation-pending';

    if not found then
        raise exception 'pending event invitation not found';
    end if;

    -- Track the attendee decision
    perform insert_audit_log(
        'event_attendee_invitation_accepted',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        v_alliance_id,
        v_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_actor_user_id)
    );

    return v_alliance_id;
end;
$$ language plpgsql;

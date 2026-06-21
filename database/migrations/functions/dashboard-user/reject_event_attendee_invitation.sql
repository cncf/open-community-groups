-- Rejects a pending organizer-created event invitation.
create or replace function reject_event_attendee_invitation(
    p_actor_user_id uuid,
    p_event_id uuid
)
returns void as $$
declare
    v_alliance_id uuid;
    v_group_id uuid;
begin
    -- Resolve event scope for auditing
    select
        g.alliance_id,
        e.group_id
    into
        v_alliance_id,
        v_group_id
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and e.deleted = false;

    if not found then
        raise exception 'event not found';
    end if;

    -- Reject the pending invitation
    update event_attendee
    set status = 'invitation-rejected'
    where event_id = p_event_id
    and user_id = p_actor_user_id
    and status = 'invitation-pending';

    if not found then
        raise exception 'pending event invitation not found';
    end if;

    -- Track the attendee decision
    perform insert_audit_log(
        'event_attendee_invitation_rejected',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        v_alliance_id,
        v_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_actor_user_id)
    );
end;
$$ language plpgsql;

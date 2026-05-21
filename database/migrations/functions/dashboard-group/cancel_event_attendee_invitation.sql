-- Cancels a pending organizer-created event invitation.
create or replace function cancel_event_attendee_invitation(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_community_id uuid;
begin
    -- Lock the event and verify it belongs to the selected group
    select g.community_id
    into v_community_id
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    for update of e;

    if not found then
        raise exception 'event not found';
    end if;

    -- Only pending invitations can be canceled
    update event_attendee
    set
        manually_invited = false,
        status = 'invitation-canceled'
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'invitation-pending';

    if not found then
        raise exception 'pending event invitation not found';
    end if;

    -- Track the cancellation
    perform insert_audit_log(
        'event_attendee_invitation_canceled',
        p_actor_user_id,
        'user',
        p_user_id,
        v_community_id,
        p_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_user_id)
    );
end;
$$ language plpgsql;

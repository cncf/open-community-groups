-- Rejects an event invitation request.
create or replace function reject_event_invitation_request(
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
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and e.canceled = false
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Mark only pending requests as rejected
    update event_invitation_request
    set
        reviewed_at = current_timestamp,
        reviewed_by = p_actor_user_id,
        status = 'rejected'
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'pending';

    if not found then
        raise exception 'pending invitation request not found';
    end if;

    -- Track the organizer decision
    perform insert_audit_log(
        'event_invitation_request_rejected',
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

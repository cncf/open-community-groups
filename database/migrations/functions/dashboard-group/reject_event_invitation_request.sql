-- Rejects an event invitation request.
create or replace function reject_event_invitation_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
begin
    -- Lock the event and verify it belongs to the selected group
    perform lock_manageable_event(p_group_id, p_event_id, false);

    -- Mark only pending requests as rejected
    update event_invitation_request
    set
        reviewed_at = current_timestamp,
        reviewed_by = p_actor_user_id,
        status = 'rejected'
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'pending';

    -- Reject requests that are missing or already reviewed
    if not found then
        raise exception 'pending invitation request not found' using errcode = 'OCG01';
    end if;

    -- Track the organizer decision
    perform insert_audit_log(
        'event_invitation_request_rejected',
        p_actor_user_id,
        'user',
        p_user_id,
        p_group_id => p_group_id,
        p_event_id => p_event_id,
        p_details => jsonb_build_object('event_id', p_event_id, 'user_id', p_user_id)
    );
end;
$$ language plpgsql;

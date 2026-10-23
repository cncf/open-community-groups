-- delete_event performs a soft delete on an event by setting deleted=true and deleted_at.
create or replace function delete_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
begin
    -- Lock the event, canceled or not, to serialize state transitions
    perform lock_manageable_event(p_group_id, p_event_id, true);

    -- Enforce cancellation and refund settlement before destructive removal
    if get_event_delete_eligibility(p_group_id, p_event_id) <> 'allowed' then
        raise exception 'event must be canceled and all payment work settled before deletion' using errcode = 'OCG01';
    end if;

    -- Close open and event-canceled co-host invitations before deleting the event
    perform close_event_cohosts(p_actor_user_id, p_event_id, 'event-deleted');

    -- Update event to mark as deleted
    update event set
        deleted = true,
        deleted_at = current_timestamp,
        published = false
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false;

    -- Request provider deletion of the event and session meetings
    perform mark_event_meetings_out_of_sync(p_event_id);

    -- Track the event deletion
    perform insert_audit_log(
        'event_deleted',
        p_actor_user_id,
        'event',
        p_event_id,
        p_group_id => p_group_id,
        p_event_id => p_event_id
    );
end;
$$ language plpgsql;

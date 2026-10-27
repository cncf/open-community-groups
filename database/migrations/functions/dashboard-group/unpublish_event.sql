-- unpublish_event sets published=false and clears publication metadata for an event.
create or replace function unpublish_event(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
declare
    v_published boolean;
begin
    -- Lock the event, canceled or not, and load its publication state
    v_published := (lock_manageable_event(p_group_id, p_event_id, true)).published;

    -- Keep repeated unpublish requests idempotent
    if not v_published then
        return;
    end if;

    -- Cancel active offers, expire checkouts, and clear enrollment queues
    perform close_event_enrollment(p_actor_user_id, p_event_id);

    -- Update event to mark as unpublished
    update event set
        published = false,
        published_at = null,
        published_by = null
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false;

    -- Request provider deletion of the event and session meetings
    perform mark_event_meetings_out_of_sync(p_event_id);

    -- Track the unpublish action
    perform insert_audit_log(
        'event_unpublished',
        p_actor_user_id,
        'event',
        p_event_id,
        p_group_id => p_group_id,
        p_event_id => p_event_id
    );
end;
$$ language plpgsql;

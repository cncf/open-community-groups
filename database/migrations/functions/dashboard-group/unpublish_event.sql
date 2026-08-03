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
    -- Lock and load the current publication state
    select published
    into v_published
    from event
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    for update;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Keep repeated unpublish requests idempotent
    if not v_published then
        return;
    end if;

    -- Cancel active offers, expire checkouts, and clear enrollment queues
    perform close_event_enrollment(p_actor_user_id, p_event_id);

    -- Update event to mark as unpublished
    -- Also set meeting_in_sync to false to trigger meeting deletion when applicable
    update event set
        meeting_in_sync = case
            when meeting_requested = true then false
            else meeting_in_sync
        end,
        published = false,
        published_at = null,
        published_by = null
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false;

    -- Mark sessions as out of sync to trigger meeting deletion
    update session set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;

    -- Track the unpublish action
    perform insert_audit_log(
        'event_unpublished',
        p_actor_user_id,
        'event',
        p_event_id,
        (select community_id from "group" where group_id = p_group_id),
        p_group_id,
        p_event_id
    );
end;
$$ language plpgsql;

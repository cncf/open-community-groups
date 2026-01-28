-- delete_event performs a soft delete on an event by setting deleted=true and deleted_at.
create or replace function delete_event(
    p_group_id uuid,
    p_event_id uuid
)
returns void as $$
begin
    -- Lock event row to serialize state transitions
    perform 1
    from event
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    for update;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Update event to mark as deleted
    -- If meeting was requested, mark meeting_in_sync as false to trigger deletion
    update event set
        deleted = true,
        deleted_at = current_timestamp,
        published = false,
        meeting_in_sync = case
            when meeting_requested = true then false
            else meeting_in_sync
        end
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false;

    -- Mark sessions as out of sync to trigger meeting deletion
    update session set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;
end;
$$ language plpgsql;

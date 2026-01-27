-- cancel_event marks an event as canceled and clears publication metadata.
create or replace function cancel_event(
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

    -- Update event to mark as canceled
    -- If meeting was requested, mark meeting_in_sync as false to trigger deletion
    update event set
        canceled = true,
        published = false,
        published_at = null,
        published_by = null,
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

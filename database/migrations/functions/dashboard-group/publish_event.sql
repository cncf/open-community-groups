-- publish_event sets published=true and records publication metadata for an event.
create or replace function publish_event(
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
begin
    -- Update event to mark as published
    -- Also set meeting_in_sync to false to trigger meeting setup when applicable
    update event set
        meeting_in_sync = case
            when meeting_requested = true then false
            else meeting_in_sync
        end,
        published = true,
        published_at = now(),
        published_by = p_user_id
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Mark sessions as out of sync to trigger meeting creation
    update session set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;
end;
$$ language plpgsql;


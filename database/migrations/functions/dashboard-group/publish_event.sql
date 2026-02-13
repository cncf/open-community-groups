-- publish_event sets published=true and records publication metadata for an event.
create or replace function publish_event(
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_starts_at timestamptz;
begin
    -- Check if the event is active and lock it for update
    select starts_at
    into v_starts_at
    from event
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false
    for update;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Check that the event has a start date
    if v_starts_at is null then
        raise exception 'event must have a start date to be published';
    end if;

    -- Update event to mark as published
    -- Also set meeting_in_sync to false to trigger meeting setup when applicable
    update event set
        meeting_in_sync = case
            when meeting_requested = true then false
            else meeting_in_sync
        end,
        published = true,
        published_at = now(),
        published_by = p_user_id,
        -- Mark reminder as evaluated when publish happens inside the 24-hour window
        event_reminder_evaluated_for_starts_at = case
            when event_reminder_enabled = true
                 and event_reminder_sent_at is null
                 and starts_at > current_timestamp
                 and starts_at <= current_timestamp + interval '24 hours'
            then starts_at
            else event_reminder_evaluated_for_starts_at
        end
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    -- Mark sessions as out of sync to trigger meeting creation
    update session set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;
end;
$$ language plpgsql;

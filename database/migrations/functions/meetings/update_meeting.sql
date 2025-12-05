-- update_meeting updates a meeting and marks the event/session as synced.
create or replace function update_meeting(
    p_meeting_id uuid,
    p_provider_meeting_id text,
    p_url text,
    p_password text,
    p_event_id uuid,
    p_session_id uuid
) returns void as $$
begin
    -- Update meeting
    update meeting
    set provider_meeting_id = p_provider_meeting_id,
        join_url = p_url,
        password = p_password,
        updated_at = current_timestamp
    where meeting_id = p_meeting_id;

    -- Mark event as synced (in the case of event meeting)
    if p_event_id is not null then
        update event
        set meeting_in_sync = true, meeting_error = null
        where event_id = p_event_id;
    end if;

    -- Mark session as synced (in the case of session meeting)
    if p_session_id is not null then
        update session
        set meeting_in_sync = true, meeting_error = null
        where session_id = p_session_id;
    end if;
end;
$$ language plpgsql;

-- delete_meeting deletes a meeting and marks the event/session as synced.
create or replace function delete_meeting(
    p_meeting_id uuid,
    p_event_id uuid,
    p_session_id uuid
) returns void as $$
begin
    -- Delete meeting (if one exists)
    if p_meeting_id is not null then
        delete from meeting where meeting_id = p_meeting_id;
    end if;

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

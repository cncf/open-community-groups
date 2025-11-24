-- add_meeting adds a new meeting and marks the event/session as synced.
create or replace function add_meeting(
    p_provider_meeting_id text,
    p_url text,
    p_password text,
    p_event_id uuid,
    p_session_id uuid
) returns void as $$
begin
    -- Insert new meeting
    insert into meeting (provider_meeting_id, join_url, password, event_id, session_id)
    values (p_provider_meeting_id, p_url, p_password, p_event_id, p_session_id);

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

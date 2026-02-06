-- set_meeting_error records a sync error and marks the target as in sync.
create or replace function set_meeting_error(
    p_error text,
    p_event_id uuid,
    p_meeting_id uuid,
    p_session_id uuid
)
returns void as $$
begin
    -- Event meeting case
    if p_event_id is not null then
        update event
        set meeting_error = p_error, meeting_in_sync = true
        where event_id = p_event_id;
    -- Session meeting case
    elsif p_session_id is not null then
        update session
        set meeting_error = p_error, meeting_in_sync = true
        where session_id = p_session_id;
    -- Orphan meeting case: no event/session to record error on, delete the row
    elsif p_meeting_id is not null then
        delete from meeting
        where meeting_id = p_meeting_id;
    end if;
end;
$$ language plpgsql;

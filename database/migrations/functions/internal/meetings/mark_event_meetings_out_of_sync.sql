-- Marks the requested meetings of an event and of its sessions out of sync so
-- the meetings worker creates, updates or deletes them after a lifecycle
-- change (publish, unpublish, cancel, delete). Meetings that were never
-- requested keep their sync state. Callers hold the event row lock.
create or replace function mark_event_meetings_out_of_sync(p_event_id uuid)
returns void as $$
begin
    -- Request provider work for the event meeting
    update event
    set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;

    -- Request provider work for the session meetings
    update session
    set meeting_in_sync = false
    where event_id = p_event_id
    and meeting_requested = true;
end;
$$ language plpgsql;

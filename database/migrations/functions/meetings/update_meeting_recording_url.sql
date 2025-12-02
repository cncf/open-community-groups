-- update_meeting_recording_url updates the recording URL for a meeting
-- identified by its provider meeting ID (e.g., Zoom meeting ID).
create or replace function update_meeting_recording_url(
    p_provider_meeting_id text,
    p_recording_url text
) returns void as $$
begin
    update meeting
    set recording_url = p_recording_url,
        updated_at = current_timestamp
    where provider_meeting_id = p_provider_meeting_id;
end;
$$ language plpgsql;

-- update_meeting_recording_url updates the recording URL for a meeting
-- identified by its provider and provider meeting ID (e.g., Zoom meeting ID).
create or replace function update_meeting_recording_url(
    p_meeting_provider_id text,
    p_provider_meeting_id text,
    p_recording_url text
) returns void as $$
    update meeting
    set recording_url = p_recording_url,
        updated_at = current_timestamp
    where meeting_provider_id = p_meeting_provider_id
      and provider_meeting_id = p_provider_meeting_id;
$$ language sql;

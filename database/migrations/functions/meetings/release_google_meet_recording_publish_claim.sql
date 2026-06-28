-- release_google_meet_recording_publish_claim releases a retryable recording
-- publish claim and records the latest discovery/upload error.
create or replace function release_google_meet_recording_publish_claim(
    p_meeting_id uuid,
    p_recording_publish_claimed_at timestamptz,
    p_error text
) returns void as $$
    update meeting
    set recording_publish_claimed_at = null,
        recording_publish_checked_at = current_timestamp,
        recording_publish_error = nullif(btrim(p_error), ''),
        updated_at = current_timestamp
    where meeting_id = p_meeting_id
      and recording_publish_claimed_at = p_recording_publish_claimed_at;
$$ language sql;

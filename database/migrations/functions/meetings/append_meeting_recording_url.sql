-- Appends a raw recording URL for a meeting.
create or replace function append_meeting_recording_url(
    p_meeting_provider_id text,
    p_provider_meeting_id text,
    p_recording_url text
) returns void as $$
    -- Normalize input and skip blanks
    with input as (
        select nullif(btrim(p_recording_url), '') as recording_url
    )
    update meeting
    set recording_urls = array_append(recording_urls, input.recording_url),
        updated_at = current_timestamp
    from input
    where meeting_provider_id = p_meeting_provider_id
      and provider_meeting_id = p_provider_meeting_id
      and input.recording_url is not null
      -- Keep raw recording URLs unique per meeting
      and array_position(recording_urls, input.recording_url) is null;
$$ language sql;

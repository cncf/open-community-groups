-- mark_google_meet_recording_published completes a Google Meet recording
-- publish claim and stores the resulting YouTube URL on the linked event/session.
create or replace function mark_google_meet_recording_published(
    p_meeting_id uuid,
    p_recording_publish_claimed_at timestamptz,
    p_drive_file_id text,
    p_youtube_url text
) returns void as $$
declare
    v_drive_file_id text := nullif(btrim(p_drive_file_id), '');
    v_youtube_url text := nullif(btrim(p_youtube_url), '');
begin
    if v_drive_file_id is null then
        raise exception 'drive file id cannot be empty';
    end if;

    if v_youtube_url is null then
        raise exception 'youtube url cannot be empty';
    end if;

    with updated_meeting as (
        update meeting
        set recording_publish_claimed_at = null,
            recording_publish_checked_at = current_timestamp,
            recording_publish_drive_file_id = v_drive_file_id,
            recording_publish_error = null,
            recording_publish_url = v_youtube_url,
            recording_urls = case
                when array_position(recording_urls, v_youtube_url) is null
                then array_append(recording_urls, v_youtube_url)
                else recording_urls
            end,
            updated_at = current_timestamp
        where meeting_id = p_meeting_id
          and recording_publish_claimed_at = p_recording_publish_claimed_at
        returning event_id, session_id
    )
    update event e
    set meeting_recording_url = coalesce(e.meeting_recording_url, v_youtube_url),
        meeting_recording_published = true
    from updated_meeting um
    where e.event_id = um.event_id;

    with updated_meeting as (
        select event_id, session_id
        from meeting
        where meeting_id = p_meeting_id
          and recording_publish_url = v_youtube_url
    )
    update session s
    set meeting_recording_url = coalesce(s.meeting_recording_url, v_youtube_url),
        meeting_recording_published = true
    from updated_meeting um
    where s.session_id = um.session_id;
end;
$$ language plpgsql;
